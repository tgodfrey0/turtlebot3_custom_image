use std::error::Error;
use std::fs::OpenOptions;
use std::io::{self, BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Sender};
use std::thread;
use std::time::{Duration, Instant};

use crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode};
use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Alignment, Constraint, Direction, Layout};
use ratatui::style::{Color, Style};
use ratatui::text::{Span, Spans};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, Paragraph, Wrap};
use ratatui::Terminal;

const ROS_DISTROS: &[&str] = &["disabled", "foxy", "humble", "jazzy", "rolling"];

enum Mode {
    Normal,
    Editing { field: usize, buffer: String },
    Selecting { field: usize, options: Vec<String>, idx: usize },
    Previewing { lines: Vec<String>, done: bool },
    WifiAdd { ssid: String, pass: String, step: u8 },
}

struct App {
    selected: usize,

    profile: String,
    robot_model: String,
    machine: String,
    hostname_prefix: String,
    image_name: String,
    robot_user: String,
    robot_pass: String,
    networks: Vec<(String, String)>,
    tailscale: bool,
    tailscale_authkey: String,
    ros_distro: Option<String>,

    message: String,
    mode: Mode,

    output: Vec<String>,
    building: bool,
    build_pid: Option<u32>,
    build_started: Option<Instant>,
    build_exit_code: Option<i32>,
    build_count: usize,
    task_current: usize,
    task_total: usize,
    log_file: Option<std::fs::File>,
}

impl Default for App {
    fn default() -> Self {
        let machines = default_machines();
        let log_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open("build-output.log")
            .ok();
        Self {
            selected: 0,
            profile: "generic".into(),
            robot_model: "generic".into(),
            machine: machines.get(0).map(|(v, _)| v.clone()).unwrap_or_else(|| "raspberrypi4-64".into()),
            hostname_prefix: "robot".into(),
            image_name: "uav_companion".into(),
            robot_user: "robot".into(),
            robot_pass: "changeme".into(),
            networks: Vec::new(),
            tailscale: true,
            tailscale_authkey: "".into(),
            ros_distro: None,
            message: "Enter=edit/select, Space=toggle, i=import, a=add-wifi, p=preview, e=export, b=build, q=quit".into(),
            mode: Mode::Normal,
            output: Vec::new(),
            building: false,
            build_pid: None,
            build_started: None,
            build_exit_code: None,
            build_count: 0,
            task_current: 0,
            task_total: 0,
            log_file,
        }
    }
}

const BASE_FIELDS: usize = 7;
const FLAG_FIELDS: usize = 3;

impl App {
    fn field_count(&self) -> usize {
        BASE_FIELDS + self.networks.len() + FLAG_FIELDS
    }

    fn push_output(&mut self, line: String) {
        if let Some(idx) = line.find("Running task ") {
            let rest = &line[idx + 13..];
            if let Some(end) = rest.find(" of ") {
                if let Ok(cur) = rest[..end].parse::<usize>() {
                    let after = &rest[end + 4..];
                    if let Some(paren) = after.find(' ') {
                        if let Ok(total) = after[..paren].parse::<usize>() {
                            self.task_current = cur;
                            self.task_total = total;
                        }
                    }
                }
            }
        }
        if let Some(ref mut f) = self.log_file {
            let _ = writeln!(f, "{}", line);
        }
        self.output.push(line);
    }
}

fn default_machines() -> Vec<(String, String)> {
    vec![
        ("raspberrypi4-64".into(), "Raspberry Pi 4 (Pi 4, CM4, 400)".into()),
        ("raspberrypi5".into(), "Raspberry Pi 5 (Pi 5, CM5, 500)".into()),
    ]
}

fn machine_display_list() -> Vec<String> {
    default_machines().iter().map(|(val, desc)| format!("{} — {}", val, desc)).collect()
}

fn machine_from_selection(selection: &str) -> String {
    selection.split(" — ").next().unwrap_or(selection).to_string()
}

fn models_for_profile(profile: &str) -> Vec<String> {
    match profile {
        "turtlebot3" => vec!["burger", "waffle", "waffle_pi"].into_iter().map(|s| s.into()).collect(),
        _ => vec!["generic".into()],
    }
}

/// Each robot profile maps to its own curated kas yml (which pulls in the
/// shared robot-settings.yml fragment, the right layers, distro and target).
fn config_for_profile(profile: &str) -> &'static str {
    match profile {
        "turtlebot3" => "configs/kas/turtlebot3.yml",
        _ => "configs/kas/build-config.yml",
    }
}

fn robot_types() -> Vec<String> {
    vec!["generic".into(), "turtlebot3".into()]
}

/// Patch only the top-level `machine:` scalar of the selected profile yml.
/// Everything else (distro, target, repos, includes, tunables) is owned by
/// the tracked kas configs; remaining fields are applied by build.sh flags.
fn generate_kas_config(app: &App) -> Result<(), String> {
    let path = config_for_profile(&app.profile);
    let content = std::fs::read_to_string(path)
        .map_err(|e| format!("Failed to read {}: {}", path, e))?;

    let mut out = String::with_capacity(content.len());
    let mut patched = false;
    for line in content.lines() {
        if line.starts_with("machine:") {
            out.push_str(&format!("machine: {}\n", app.machine));
            patched = true;
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    if !patched {
        return Err(format!("No 'machine:' scalar found in {}", path));
    }

    std::fs::write(path, out).map_err(|e| format!("Failed to write {}: {}", path, e))?;
    Ok(())
}

fn load_config_from_file(path: &str, app: &mut App) -> Result<String, String> {
    let content = std::fs::read_to_string(path).map_err(|e| format!("Failed to read file: {}", e))?;
    
    app.networks.clear();

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with("kas_command") || line.starts_with("git_hash") || line.starts_with("timestamp") {
            continue;
        }
        
        if let Some(idx) = line.find(':') {
            let key = line[..idx].trim();
            let val = line[idx+1..].trim();
            
            match key {
                "profile" => app.profile = val.to_string(),
                "machine" => app.machine = val.to_string(),
                "robot_type" => app.robot_model = val.to_string(),
                "image_name" => app.image_name = val.to_string(),
                "hostname_prefix" => app.hostname_prefix = val.to_string(),
                "robot_user" => app.robot_user = val.to_string(),
                "robot_pass" => app.robot_pass = val.to_string(),
                "tailscale_enabled" => app.tailscale = val == "1",
                "ros_distro" => {
                    if val == "disabled" || val.is_empty() {
                        app.ros_distro = None;
                    } else {
                        app.ros_distro = Some(val.to_string());
                    }
                }
                k if k.starts_with("wifi_") && k.ends_with("_ssid") => {
                    if !val.is_empty() {
                        let idx: usize = k[5..].trim_end_matches("_ssid").parse().unwrap_or(0);
                        while app.networks.len() <= idx {
                            app.networks.push((String::new(), String::new()));
                        }
                        app.networks[idx].0 = val.to_string();
                    }
                }
                k if k.starts_with("wifi_") && k.ends_with("_pass") => {
                    let idx: usize = k[5..].trim_end_matches("_pass").parse().unwrap_or(0);
                    while app.networks.len() <= idx {
                        app.networks.push((String::new(), String::new()));
                    }
                    app.networks[idx].1 = val.to_string();
                }
                _ => {}
            }
        }
    }

    app.networks.retain(|(s, _)| !s.is_empty());
    
    Ok(format!("Imported configuration from {}", path))
}

fn zenity_file() -> Option<String> {
    let cwd = std::env::current_dir().ok()?;
    let start = format!("{}/", cwd.to_string_lossy());
    let out = Command::new("zenity")
        .args(&["--file-selection", &format!("--filename={}", start), "--title=Select config file"])
        .output()
        .ok()?;
    if out.status.success() {
        let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if path.is_empty() { None } else { Some(path) }
    } else {
        None
    }
}

fn zenity_dir() -> Option<String> {
    let cwd = std::env::current_dir().ok()?;
    let start = format!("{}/", cwd.to_string_lossy());
    let out = Command::new("zenity")
        .args(&["--file-selection", "--directory", &format!("--filename={}", start), "--title=Select output directory"])
        .output()
        .ok()?;
    if out.status.success() {
        let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if path.is_empty() { None } else { Some(path) }
    } else {
        None
    }
}

fn find_build_sh() -> Option<PathBuf> {
    if let Ok(mut dir) = std::env::current_dir() {
        for _ in 0..6 {
            let candidate = dir.join("build.sh");
            if candidate.exists() {
                return Some(candidate);
            }
            if !dir.pop() { break; }
        }
    }
    None
}

fn spawn_build(tx: Sender<String>, args: Vec<String>) {
    thread::spawn(move || {
        if let Some(build) = find_build_sh() {
            let mut cmd = Command::new(build);
            cmd.args(&args);
            cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
            match cmd.spawn() {
                Ok(mut child) => {
                    let pid = child.id();
                    let _ = tx.send(format!("__BUILD_PID__:{}", pid));
                    if let Some(out) = child.stdout.take() {
                        let txo = tx.clone();
                        thread::spawn(move || {
                            let reader = BufReader::new(out);
                            for line in reader.lines() {
                                let l = line.unwrap_or_default();
                                let _ = txo.send(l);
                            }
                        });
                    }
                    if let Some(err) = child.stderr.take() {
                        let txe = tx.clone();
                        thread::spawn(move || {
                            let reader = BufReader::new(err);
                            for line in reader.lines() {
                                let l = line.unwrap_or_default();
                                let _ = txe.send(l);
                            }
                        });
                    }
                    match child.wait() {
                        Ok(status) => {
                            let code = status.code().unwrap_or(-1);
                            let _ = tx.send(format!("__BUILD_DONE__:{}", code));
                        }
                        Err(e) => {
                            let _ = tx.send(format!("Build failed to wait: {}", e));
                            let _ = tx.send("__BUILD_DONE__:-1".to_string());
                        }
                    }
                }
                Err(e) => {
                    let _ = tx.send(format!("Failed to spawn build: {}", e));
                    let _ = tx.send("__BUILD_DONE__:-1".to_string());
                }
            }
        } else {
            let _ = tx.send("build.sh not found".to_string());
            let _ = tx.send("__BUILD_DONE__:-1".to_string());
        }
    });
}

fn spawn_preview(tx: Sender<String>, args: Vec<String>) {
    thread::spawn(move || {
        if let Some(build) = find_build_sh() {
            let mut cmd = Command::new(build);
            cmd.args(&args);
            cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
            match cmd.spawn() {
                Ok(mut child) => {
                    if let Some(out) = child.stdout.take() {
                        let txo = tx.clone();
                        thread::spawn(move || {
                            let reader = BufReader::new(out);
                            for line in reader.lines() {
                                let l = line.unwrap_or_default();
                                let _ = txo.send(l);
                            }
                        });
                    }
                    if let Some(err) = child.stderr.take() {
                        let txe = tx.clone();
                        thread::spawn(move || {
                            let reader = BufReader::new(err);
                            for line in reader.lines() {
                                let l = line.unwrap_or_default();
                                let _ = txe.send(l);
                            }
                        });
                    }
                    match child.wait() {
                        Ok(status) => {
                            let code = status.code().unwrap_or(-1);
                            let _ = tx.send(format!("__PREVIEW_DONE__:{}", code));
                        }
                        Err(e) => {
                            let _ = tx.send(format!("Preview failed to wait: {}", e));
                            let _ = tx.send("__PREVIEW_DONE__:-1".to_string());
                        }
                    }
                }
                Err(e) => {
                    let _ = tx.send(format!("Failed to spawn preview: {}", e));
                    let _ = tx.send("__PREVIEW_DONE__:-1".to_string());
                }
            }
        } else {
            let _ = tx.send("build.sh not found".to_string());
            let _ = tx.send("__PREVIEW_DONE__:-1".to_string());
        }
    });
}

fn run_zenity<F>(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, f: F) -> Option<String>
where
    F: FnOnce() -> Option<String>,
{
    disable_raw_mode().ok()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    ).ok()?;
    terminal.show_cursor().ok()?;

    let result = f();

    enable_raw_mode().ok()?;
    execute!(
        terminal.backend_mut(),
        EnterAlternateScreen,
        EnableMouseCapture
    ).ok()?;
    terminal.hide_cursor().ok()?;
    terminal.clear().ok()?;

    result
}

fn build_common_args(app: &App) -> Vec<String> {
    let mut args = Vec::new();
    args.push("--config".into()); args.push(config_for_profile(&app.profile).into());
    args.push("--machine".into()); args.push(app.machine.clone());
    args.push("--image-name".into()); args.push(app.image_name.clone());
    args.push("--hostname".into()); args.push(app.hostname_prefix.clone());
    args.push("--robot-model".into()); args.push(app.robot_model.clone());
    args.push("--robot-user".into()); args.push(app.robot_user.clone());
    args.push("--robot-pass".into()); args.push(app.robot_pass.clone());
    for (s, p) in app.networks.iter() {
        args.push("--wifi".into()); args.push(s.clone()); args.push(p.clone());
    }
    if !app.tailscale_authkey.is_empty() { args.push("--authkey".into()); args.push(app.tailscale_authkey.clone()); }
    args.push("--tailscale-enabled".into()); args.push((if app.tailscale {"1"} else {"0"}).into());
    if let Some(ref distro) = app.ros_distro {
        args.push("--ros-distro".into()); args.push(distro.clone());
    }
    let opencr = app.profile == "turtlebot3";
    args.push("--opencr-enabled".into()); args.push((if opencr {"1"} else {"0"}).into());
    args
}

fn build_export_args(app: &App, outdir: &str) -> Vec<String> {
    let mut args = build_common_args(app);
    args.push("--no-build".into());
    args.push("--outdir".into()); args.push(outdir.into());
    args
}

fn main() -> Result<(), Box<dyn Error>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App::default();
    let (tx, rx) = mpsc::channel::<String>();
    let tick_rate = Duration::from_millis(200);
    let mut last_tick = Instant::now();

    loop {
        while let Ok(line) = rx.try_recv() {
            if line.starts_with("__BUILD_PID__:") {
                if let Some(pid) = line.split(':').nth(1).and_then(|s| s.parse().ok()) {
                    app.build_pid = Some(pid);
                }
            } else if line.starts_with("__BUILD_DONE__:") {
                app.building = false;
                app.build_pid = None;
                app.build_started = None;
                app.build_count += 1;
                if let Some(code) = line.split(':').nth(1).and_then(|s| s.parse().ok()) {
                    app.build_exit_code = Some(code);
                    app.message = format!("Build finished (exit {})", code);
                }
            } else if line.starts_with("__PREVIEW_DONE__:") {
                if let Some(code) = line.split(':').nth(1) {
                    if let Mode::Previewing { lines: _, done } = &mut app.mode {
                        *done = true;
                        app.message = format!("Preview finished (exit {})", code);
                    } else {
                        app.message = format!("Preview finished (exit {})", code);
                    }
                }
            } else {
                match &mut app.mode {
                    Mode::Previewing { lines, .. } => lines.push(line),
                    _ => app.push_output(line),
                }
            }
        }

        terminal.draw(|f| {
            let size = f.size();
            let bg = Paragraph::new("").block(Block::default().style(Style::default().bg(Color::Rgb(40,40,40))));
            f.render_widget(bg, size);

            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Percentage(33), Constraint::Min(3), Constraint::Percentage(64)].as_ref())
                .split(size);

            let top_cols = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(66), Constraint::Percentage(34)].as_ref())
                .split(chunks[0]);

            let right_split = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Percentage(50), Constraint::Percentage(50)].as_ref())
                .split(top_cols[1]);

            let ros_label = match &app.ros_distro {
                None => "disabled".to_string(),
                Some(d) => d.clone(),
            };

            let mut params = vec![
                format!("Robot: {}", app.profile),
                format!("Robot Model: {}", app.robot_model),
                format!("Machine: {}", app.machine),
                format!("Hostname Prefix: {}", app.hostname_prefix),
                format!("Image Name: {}", app.image_name),
                format!("User: {}", app.robot_user),
                format!("Password: {}", "****"),
            ];

            for (i, (s, p)) in app.networks.iter().enumerate() {
                params.push(format!("WiFi {}: {} ({})", i, s, if p.is_empty() {"no-pass"} else {"pass-set"}));
            }

            params.push(format!("Tailscale: {}", if app.tailscale {"enabled"} else {"disabled"}));
            params.push(format!("Tailscale key: {}", if app.tailscale_authkey.is_empty() {"(none)"} else {"(set)"}));
            params.push(format!("ROS2: {}", ros_label));

            let param_items: Vec<ListItem> = params.iter().map(|p| ListItem::new(Spans::from(Span::raw(p.clone())))).collect();
            let mut list_state = ratatui::widgets::ListState::default();
            if app.selected < params.len() { list_state.select(Some(app.selected)); } else { list_state.select(None); }
            let param_list = List::new(param_items)
                .block(Block::default().borders(Borders::ALL).title("Parameters"))
                .highlight_style(Style::default().bg(Color::Green).fg(Color::Black));
            f.render_stateful_widget(param_list, top_cols[0], &mut list_state);

            let progress_line = if app.task_total > 0 {
                let pct = (app.task_current * 100) / app.task_total;
                let bar_width = 20;
                let filled = (app.task_current * bar_width) / app.task_total;
                let empty = bar_width - filled;
                let bar: String = "#".repeat(filled) + &"-".repeat(empty);
                format!("[{}] {}/{} ({}%)", bar, app.task_current, app.task_total, pct)
            } else if app.building {
                "Waiting for tasks...".to_string()
            } else {
                "".to_string()
            };
            let status_line = if app.building {
                match app.build_started {
                    Some(start) => {
                        let elapsed = start.elapsed();
                        let mins = elapsed.as_secs() / 60;
                        let secs = elapsed.as_secs() % 60;
                        format!("Building...  {:02}:{:02}", mins, secs)
                    }
                    None => "Building...".to_string(),
                }
            } else {
                match app.build_exit_code {
                    Some(0) => "Last build: OK".to_string(),
                    Some(n) => format!("Last build: failed ({})", n),
                    None => "Idle".to_string(),
                }
            };
            let mut stats_text = vec![
                Spans::from(Span::raw(format!("Status: {}", status_line))),
            ];
            if !progress_line.is_empty() {
                stats_text.push(Spans::from(Span::raw(format!("Tasks: {}", progress_line))));
            }
            let stats_para = Paragraph::new(stats_text).block(Block::default().borders(Borders::ALL).title("Stats"));
            f.render_widget(stats_para, right_split[0]);

            let action_items = vec![
                ListItem::new(Spans::from(Span::raw("p: preview"))),
                ListItem::new(Spans::from(Span::raw("e: export"))),
                ListItem::new(Spans::from(Span::raw("b: build"))),
                ListItem::new(Spans::from(Span::raw("i: import"))),
                ListItem::new(Spans::from(Span::raw("a: add WiFi"))),
                ListItem::new(Spans::from(Span::raw("q: quit"))),
                ListItem::new(Spans::from(Span::raw(""))),
                ListItem::new(Spans::from(Span::raw("Enter: edit/select"))),
                ListItem::new(Spans::from(Span::raw("Space: toggle"))),
            ];
            let actions = List::new(action_items)
                .block(Block::default().borders(Borders::ALL).title("Actions"));
            f.render_widget(actions, right_split[1]);

            let out_lines: Vec<Spans> = app.output.iter().rev().take(chunks[2].height as usize - 2).rev().map(|l| Spans::from(Span::raw(l.clone()))).collect();
            let output_para = Paragraph::new(out_lines).block(Block::default().borders(Borders::ALL).title(if app.building {"Output (building)..."} else {"Output"})).wrap(Wrap { trim: true });
            f.render_widget(output_para, chunks[2]);

            let msg_style = if app.message.contains("failed") || app.message.contains("Failed") {
                Style::default().fg(Color::Red)
            } else if app.message.contains("finished") || app.message.contains("OK") {
                Style::default().fg(Color::Green)
            } else {
                Style::default().fg(Color::Yellow)
            };
            let msg_para = Paragraph::new(Spans::from(Span::styled(app.message.clone(), msg_style)));
            f.render_widget(msg_para, chunks[1]);

            match &app.mode {
                Mode::Selecting { field: _, options, idx } => {
                    let area = ratatui::layout::Rect { x: size.width/8, y: size.height/6, width: size.width*3/4, height: size.height*2/5 };
                    f.render_widget(Clear, area);
                    let opts: Vec<ListItem> = options.iter().map(|o| ListItem::new(Spans::from(Span::raw(o)))).collect();
                    let mut s = ratatui::widgets::ListState::default(); s.select(Some(*idx));
                    let sel = List::new(opts).block(Block::default().borders(Borders::ALL).title("Select option")).highlight_style(Style::default().bg(Color::Green).fg(Color::Black));
                    f.render_stateful_widget(sel, area, &mut s);
                }
                Mode::Editing { field: _, buffer } => {
                    let area = ratatui::layout::Rect { x: size.width/8, y: size.height/3, width: size.width*3/4, height: 3 };
                    f.render_widget(Clear, area);
                    let p = Paragraph::new(buffer.as_str()).block(Block::default().borders(Borders::ALL).title("Edit"));
                    f.render_widget(p.alignment(Alignment::Left), area);
                }
                Mode::WifiAdd { ssid, pass, step } => {
                    let w = std::cmp::min(60, size.width.saturating_sub(10));
                    let h = 7;
                    let area = ratatui::layout::Rect {
                        x: (size.width.saturating_sub(w)) / 2,
                        y: (size.height.saturating_sub(h)) / 2,
                        width: w,
                        height: h,
                    };
                    f.render_widget(Clear, area);
                    let title = if *step == 0 { "Add WiFi - SSID (type and press Enter)" } else { "Add WiFi - Password (type and press Enter)" };
                    let content = if *step == 0 { ssid.clone() } else { pass.clone() };
                    let display = if content.is_empty() { "(empty)".to_string() } else { content };
                    let p = Paragraph::new(display).block(Block::default().borders(Borders::ALL).title(title));
                    f.render_widget(p.alignment(Alignment::Left), area);
                }
                Mode::Previewing { lines, done } => {
                    let area = ratatui::layout::Rect { x: size.width/10, y: size.height/10, width: size.width*8/10, height: size.height*8/10 };
                    f.render_widget(Clear, area);
                    let title = if *done { "Preview (done) - press Enter or Esc to close" } else { "Preview - press Enter or Esc to close" };
                    let content = if lines.is_empty() { "(no output yet)".to_string() } else { lines.join("\n") };
                    let p = Paragraph::new(content).block(Block::default().borders(Borders::ALL).title(title)).wrap(Wrap { trim: false });
                    f.render_widget(p.alignment(Alignment::Left), area);
                }
                _ => {}
            }
        })?;

        let timeout = tick_rate.checked_sub(last_tick.elapsed()).unwrap_or_else(|| Duration::from_secs(0));
        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                match &mut app.mode {
                    Mode::Normal => match key.code {
                        KeyCode::Char('q') => {
                            if let Some(pid) = app.build_pid {
                                // Kill the entire process group
                                if let Ok(out) = Command::new("ps").args(["-o", "pgid=", "-p", &pid.to_string()]).output() {
                                    if let Ok(pgid) = String::from_utf8_lossy(&out.stdout).trim().parse::<i32>() {
                                        let _ = Command::new("kill").args(["-TERM", &format!("-{}", pgid)]).status();
                                    }
                                }
                                // Fallback: kill the process directly
                                let _ = Command::new("kill").args(["-TERM", &pid.to_string()]).status();
                                app.message = "Killed build process".into();
                            }
                            break;
                        }
                        KeyCode::Down => { app.selected = (app.selected + 1) % app.field_count(); }
                        KeyCode::Up => { app.selected = if app.selected == 0 { app.field_count()-1 } else { app.selected -1 }; }
                        KeyCode::Char('a') => {
                            if app.networks.len() >= 3 {
                                app.message = "Maximum 3 WiFi networks already configured".into();
                            } else {
                                app.mode = Mode::WifiAdd { ssid: String::new(), pass: String::new(), step: 0 };
                                app.message = "Enter WiFi SSID (type and press Enter)".into();
                            }
                        }
                        KeyCode::Char('i') => {
                            if let Some(path) = run_zenity(&mut terminal, zenity_file) {
                                match load_config_from_file(&path, &mut app) {
                                    Ok(msg) => app.message = msg,
                                    Err(e) => app.message = format!("Import failed: {}", e),
                                }
                            } else {
                                app.message = "Import cancelled".into();
                            }
                        }
                        KeyCode::Char('p') => {
                            if let Mode::Previewing { .. } = &app.mode {
                                app.message = "Preview already running".into();
                            } else {
                                app.message = "Generating config and starting preview...".into();
                                if let Err(e) = generate_kas_config(&app) {
                                    app.message = format!("Config generation failed: {}", e);
                                } else {
                                    app.mode = Mode::Previewing { lines: Vec::new(), done: false };
                                    let mut args = build_common_args(&app);
                                    args.push("--dry-run".into());
                                    let _ = spawn_preview(tx.clone(), args);
                                }
                            }
                        }
                        KeyCode::Char('e') => {
                            if app.building {
                                app.message = "Build or export already running".into();
                            } else if let Some(outdir) = run_zenity(&mut terminal, zenity_dir) {
                                app.message = "Generating config and starting export...".into();
                                if let Err(e) = generate_kas_config(&app) {
                                    app.message = format!("Config generation failed: {}", e);
                                } else {
                                    app.output.clear();
                                    app.building = true;
                                    app.build_started = Some(Instant::now());
                                    app.task_current = 0;
                                    app.task_total = 0;
                                    let args = build_export_args(&app, &outdir);
                                    let _ = spawn_build(tx.clone(), args);
                                }
                            } else {
                                app.message = "Export cancelled".into();
                            }
                        }
                        KeyCode::Char('b') => {
                            if app.building {
                                app.message = "Build already running".into();
                            } else {
                                app.message = "Generating config and starting build...".into();
                                if let Err(e) = generate_kas_config(&app) {
                                    app.message = format!("Config generation failed: {}", e);
                                } else {
                                    app.output.clear();
                                    app.building = true;
                                    app.build_started = Some(Instant::now());
                                    app.task_current = 0;
                                    app.task_total = 0;
                                    let mut args = build_common_args(&app);
                                    args.push("--outdir".into()); args.push("./output".into());
                                    let _ = spawn_build(tx.clone(), args);
                                }
                            }
                        }
                        KeyCode::Enter => {
                            let wifi_count = app.networks.len();
                            let flags_base = BASE_FIELDS + wifi_count;
                            match app.selected {
                                0 => {
                                    let opts = robot_types();
                                    app.mode = Mode::Selecting { field: 0, options: opts, idx: 0 };
                                }
                                1 => {
                                    let opts = models_for_profile(&app.profile);
                                    app.mode = Mode::Selecting { field: 1, options: opts, idx: 0 };
                                }
                                2 => {
                                    let opts = machine_display_list();
                                    app.mode = Mode::Selecting { field: 2, options: opts, idx: 0 };
                                }
                                3 => { app.mode = Mode::Editing { field: 3, buffer: app.hostname_prefix.clone() } }
                                4 => { app.mode = Mode::Editing { field: 4, buffer: app.image_name.clone() } }
                                5 => { app.mode = Mode::Editing { field: 5, buffer: app.robot_user.clone() } }
                                6 => { app.mode = Mode::Editing { field: 6, buffer: app.robot_pass.clone() } }
                                i if i >= BASE_FIELDS && i < flags_base => {}
                                i if i == flags_base + 1 => { app.mode = Mode::Editing { field: i, buffer: app.tailscale_authkey.clone() } }
                                i if i == flags_base + 2 => {
                                    let current = app.ros_distro.as_deref().unwrap_or("disabled");
                                    let idx = ROS_DISTROS.iter().position(|&d| d == current).unwrap_or(0);
                                    let opts: Vec<String> = ROS_DISTROS.iter().map(|s| s.to_string()).collect();
                                    app.mode = Mode::Selecting { field: i, options: opts, idx };
                                }
                                _ => {}
                            }
                        }
                        KeyCode::Char(' ') => {
                            let wifi_count = app.networks.len();
                            let flags_base = BASE_FIELDS + wifi_count;
                            match app.selected {
                                i if i == flags_base => { app.tailscale = !app.tailscale; }
                                i if i == flags_base + 2 => {
                                    let opts: Vec<String> = ROS_DISTROS.iter().map(|s| s.to_string()).collect();
                                    let current = app.ros_distro.as_deref().unwrap_or("disabled");
                                    let idx = ROS_DISTROS.iter().position(|&d| d == current).unwrap_or(0);
                                    let next = (idx + 1) % opts.len();
                                    app.ros_distro = if ROS_DISTROS[next] == "disabled" { None } else { Some(ROS_DISTROS[next].to_string()) };
                                }
                                _ => {}
                            }
                        }
                        _ => {}
                    },
                    Mode::Selecting { field, options, idx } => match key.code {
                        KeyCode::Esc => { app.mode = Mode::Normal; }
                        KeyCode::Up => { if *idx == 0 { *idx = options.len()-1 } else { *idx -= 1 } }
                        KeyCode::Down => { *idx = (*idx + 1) % options.len() }
                        KeyCode::Enter => {
                            let val = options.get(*idx).cloned().unwrap_or_default();
                            match *field {
                                0 => {
                                    app.profile = val.clone();
                                    let models = models_for_profile(&app.profile);
                                    app.robot_model = models.get(0).cloned().unwrap_or_else(|| "generic".into());
                                }
                                1 => { app.robot_model = val.clone(); }
                                2 => app.machine = machine_from_selection(&val),
                                f if f >= BASE_FIELDS + app.networks.len() + 2 && f < BASE_FIELDS + app.networks.len() + 3 => {
                                    app.ros_distro = if val == "disabled" { None } else { Some(val) };
                                }
                                _ => {}
                            }
                            app.mode = Mode::Normal;
                        }
                        _ => {}
                    },
                    Mode::Editing { field, buffer } => match key.code {
                        KeyCode::Esc => { app.mode = Mode::Normal; }
                        KeyCode::Enter => {
                            let flags_base = BASE_FIELDS + app.networks.len();
                            match *field {
                                3 => app.hostname_prefix = buffer.clone(),
                                4 => app.image_name = buffer.clone(),
                                5 => app.robot_user = buffer.clone(),
                                6 => app.robot_pass = buffer.clone(),
                                f if f == flags_base + 1 => app.tailscale_authkey = buffer.clone(),
                                _ => {}
                            }
                            app.mode = Mode::Normal;
                        }
                        KeyCode::Backspace => { buffer.pop(); }
                        KeyCode::Char(c) => { buffer.push(c); }
                        _ => {}
                    },
                    Mode::WifiAdd { ssid, pass, step } => match key.code {
                        KeyCode::Esc => { app.mode = Mode::Normal; app.message = "WiFi add cancelled".into(); },
                        KeyCode::Enter => {
                            if *step == 0 {
                                *step = 1;
                                app.message = "Enter WiFi password (or leave empty) and press Enter to save".into();
                            } else {
                                let s = ssid.trim().to_string();
                                let p = pass.clone();
                                if !s.is_empty() {
                                    app.networks.push((s, p));
                                    app.message = format!("Added WiFi network #{}", app.networks.len()-1);
                                } else {
                                    app.message = "SSID empty, not added".into();
                                }
                                app.mode = Mode::Normal;
                            }
                        }
                        KeyCode::Backspace => {
                            if *step == 0 { ssid.pop(); } else { pass.pop(); }
                        }
                        KeyCode::Char(c) => {
                            if *step == 0 { ssid.push(c); } else { pass.push(c); }
                        }
                        _ => {},
                    },
                    Mode::Previewing { lines: _, done: _ } => match key.code {
                        KeyCode::Esc | KeyCode::Enter => { app.mode = Mode::Normal; },
                        _ => {},
                    },
                }
            }
        }

        if last_tick.elapsed() >= tick_rate { last_tick = Instant::now(); }
    }

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen, DisableMouseCapture)?;
    terminal.show_cursor()?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profiles_map_to_curated_configs() {
        assert_eq!(config_for_profile("generic"), "configs/kas/build-config.yml");
        assert_eq!(config_for_profile("turtlebot3"), "configs/kas/turtlebot3.yml");
        assert_eq!(config_for_profile("anything-else"), "configs/kas/build-config.yml");
    }
}
