use std::error::Error;
use std::io::{self, BufRead, BufReader};
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

enum Mode {
    Normal,
    Editing { field: usize, buffer: String },
    Selecting { field: usize, options: Vec<String>, idx: usize },
    Previewing { lines: Vec<String>, done: bool },
}

struct App {
    items: Vec<String>,
    selected: usize,

    // fields
    profile: String,
    machine: String,
    hostname_prefix: String,
    image_name: String,
    robot_user: String,
    robot_pass: String,
    tailscale: bool,
    tailscale_authkey: String,
    ros: bool,
    mavlink: bool,
    opencr: bool,

    message: String,
    mode: Mode,

    // UI/runtime
    output: Vec<String>,
    building: bool,
}

impl Default for App {
    fn default() -> Self {
        let profiles = load_profiles();
        let machines = default_machines();
        Self {
            items: vec![
                "Profile".into(),
                "Machine".into(),
                "Hostname prefix".into(),
                "Image name".into(),
                "User".into(),
                "Password".into(),
                "Tailscale".into(),
                "Tailscale authkey".into(),
                "ROS2".into(),
                "MAVLink".into(),
                "OpenCR".into(),
                "Actions".into(),
            ],
            selected: 0,
            profile: profiles.get(0).cloned().unwrap_or_else(|| "generic".into()),
            machine: machines.get(0).cloned().unwrap_or_else(|| "raspberrypi4-64".into()),
            hostname_prefix: "robot".into(),
            image_name: "uav_companion".into(),
            robot_user: "robot".into(),
            robot_pass: "changeme".into(),
            tailscale: true,
            tailscale_authkey: "".into(),
            ros: false,
            mavlink: false,
            opencr: false,
            message: "Enter=edit, Space=toggle, p=preview, e=export, b=build, q=quit".into(),
            mode: Mode::Normal,
            output: Vec::new(),
            building: false,
        }
    }
}

fn load_profiles() -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir("configs/kas") {
        for e in entries.flatten() {
            if let Some(name) = e.path().file_stem().and_then(|s| s.to_str()) {
                out.push(name.to_string());
            }
        }
    }
    if out.is_empty() { out.push("generic".into()); }
    out
}

fn default_machines() -> Vec<String> {
    vec![
        "raspberrypi4-64".into(),
        "raspberrypi5".into(),
        "raspberrypi-cm5".into(),
        "raspberrypi-cm5-io-board".into(),
        "jetson-orin".into(),
    ]
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
                    // stdout
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
                    // stderr
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
                    // wait
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
        // drain receiver to update output and preview modal
        while let Ok(line) = rx.try_recv() {
            if line.starts_with("__BUILD_DONE__:") {
                app.building = false;
                if let Some(code) = line.split(':').nth(1) {
                    app.message = format!("Build finished (exit {})", code);
                }
                } else if line.starts_with("__PREVIEW_DONE__:") {
                    if let Some(code) = line.split(':').nth(1) {
                        // mark preview done
                        if let Mode::Previewing { lines: _, done } = &mut app.mode {
                            *done = true;
                            app.message = format!("Preview finished (exit {})", code);
                        } else {
                            app.message = format!("Preview finished (exit {})", code);
                        }
                    }
                } else {
                    // route line to preview modal if active, otherwise to output
                    match &mut app.mode {
                        Mode::Previewing { lines, .. } => lines.push(line),
                        _ => app.output.push(line),
                    }
                }
            }

        terminal.draw(|f| {
            let size = f.size();
            // draw grey background
            let bg = Paragraph::new("").block(Block::default().style(Style::default().bg(Color::Rgb(40,40,40))));
            f.render_widget(bg, size);

            // Layout: top 1/3 for controls, bottom 2/3 for full-width output
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Percentage(33), Constraint::Percentage(67)].as_ref())
                .split(size);

            // Top area split: left = 66% (parameters, scrollable), right = 34% (actions)
            let top_cols = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(66), Constraint::Percentage(34)].as_ref())
                .split(chunks[0]);

            // render parameters as a single scrollable list in the left top area
            let params = vec![
                format!("Profile: {}", app.profile),
                format!("Machine: {}", app.machine),
                format!("Hostname Prefix: {}", app.hostname_prefix),
                format!("Image Name: {}", app.image_name),
                format!("User: {}", app.robot_user),
                format!("Password: {}", "****"),
                format!("Tailscale: {}", if app.tailscale {"enabled"} else {"disabled"}),
                format!("Tailscale key: {}", if app.tailscale_authkey.is_empty() {"(none)"} else {"(set)"}),
                format!("ROS2: {}", if app.ros {"enabled"} else {"disabled"}),
                format!("MAVLink: {}", if app.mavlink {"enabled"} else {"disabled"}),
                format!("OpenCR: {}", if app.opencr {"enabled"} else {"disabled"}),
            ];

            // Build a scrollable list of parameters (stateful) so user can navigate and it will auto-scroll
            let param_items: Vec<ListItem> = params.iter().map(|p| ListItem::new(Spans::from(Span::raw(p.clone())))).collect();
            let mut list_state = ratatui::widgets::ListState::default();
            if app.selected < params.len() { list_state.select(Some(app.selected)); } else { list_state.select(None); }
            let param_list = List::new(param_items)
                .block(Block::default().borders(Borders::ALL).title("Parameters"))
                .highlight_style(Style::default().bg(Color::Green).fg(Color::Black));
            f.render_stateful_widget(param_list, top_cols[0], &mut list_state);

            // actions box on the right (top area) as a vertical list
            let action_items = vec![
                ListItem::new(Spans::from(Span::raw("p: preview"))),
                ListItem::new(Spans::from(Span::raw("e: export"))),
                ListItem::new(Spans::from(Span::raw("b: build"))),
                ListItem::new(Spans::from(Span::raw("q: quit"))),
                ListItem::new(Spans::from(Span::raw(""))),
                ListItem::new(Spans::from(Span::raw("Enter: edit/select"))),
                ListItem::new(Spans::from(Span::raw("Space: toggle"))),
            ];
            let actions = List::new(action_items)
                .block(Block::default().borders(Borders::ALL).title("Actions"));
            f.render_widget(actions, top_cols[1]);

            // bottom output area is chunks[1] (full width)
            let out_lines: Vec<Span> = app.output.iter().rev().take(chunks[1].height as usize - 2).rev().map(|l| Span::raw(l.clone())).collect();
            let output_para = Paragraph::new(Spans::from(out_lines)).block(Block::default().borders(Borders::ALL).title(if app.building {"Output (building)..."} else {"Output"})).wrap(Wrap { trim: true });
            f.render_widget(output_para, chunks[1]);

            // draw modal if selecting or editing
            match &app.mode {
                Mode::Selecting { field: _, options, idx } => {
                    let area = ratatui::layout::Rect { x: size.width/8, y: size.height/6, width: size.width*3/4, height: size.height*2/5 };
                    f.render_widget(Clear, area); // clear background
                    // render options in a list
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
                Mode::Previewing { lines, done } => {
                    // popup occupying central area; show captured lines and status
                    let area = ratatui::layout::Rect { x: size.width/10, y: size.height/10, width: size.width*8/10, height: size.height*8/10 };
                    f.render_widget(Clear, area);
                    let title = if *done { "Preview (done) - press Enter or Esc to close" } else { "Preview - press Enter or Esc to close" };
                    let content = if lines.is_empty() { "(no output yet)".to_string() } else { lines.join("
") };
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
                        KeyCode::Char('q') => break,
                        KeyCode::Down => { app.selected = (app.selected + 1) % app.items.len(); }
                        KeyCode::Up => { app.selected = if app.selected == 0 { app.items.len()-1 } else { app.selected -1 }; }
                        KeyCode::Char('p') => {
                            // spawn a preview in a popup modal and stream its output into the modal
                            if let Mode::Previewing { .. } = &app.mode {
                                app.message = "Preview already running".into();
                            } else {
                                app.message = "Starting preview...".into();
                                app.mode = Mode::Previewing { lines: Vec::new(), done: false };
                                let mut args = Vec::new();
                                args.push("--profile".to_string()); args.push(app.profile.clone());
                                args.push("--machine".to_string()); args.push(app.machine.clone());
                                args.push("--image-name".to_string()); args.push(app.image_name.clone());
                                args.push("--hostname".to_string()); args.push(app.hostname_prefix.clone());
                                args.push("--robot-user".to_string()); args.push(app.robot_user.clone());
                                args.push("--robot-pass".to_string()); args.push(app.robot_pass.clone());
                                args.push("--tailscale-enabled".to_string()); args.push((if app.tailscale {"1"} else {"0"}).to_string());
                                args.push("--ros-enabled".to_string()); args.push((if app.ros {"1"} else {"0"}).to_string());
                                args.push("--dry-run".to_string());
                                let _ = spawn_preview(tx.clone(), args);
                            }
                        }
                        KeyCode::Char('e') => {
                            if app.building {
                                app.message = "Build or export already running".into();
                            } else {
                                app.message = "Starting export (no build)...".into();
                                app.output.clear();
                                app.building = true;
                                let mut args = Vec::new();
                                args.push("--profile".to_string()); args.push(app.profile.clone());
                                args.push("--no-build".to_string());
                                args.push("--machine".to_string()); args.push(app.machine.clone());
                                args.push("--image-name".to_string()); args.push(app.image_name.clone());
                                args.push("--hostname".to_string()); args.push(app.hostname_prefix.clone());
                                args.push("--robot-user".to_string()); args.push(app.robot_user.clone());
                                args.push("--robot-pass".to_string()); args.push(app.robot_pass.clone());
                                if !app.tailscale_authkey.is_empty() { args.push("--authkey".to_string()); args.push(app.tailscale_authkey.clone()); }
                                args.push("--tailscale-enabled".to_string()); args.push((if app.tailscale {"1"} else {"0"}).to_string());
                                args.push("--ros-enabled".to_string()); args.push((if app.ros {"1"} else {"0"}).to_string());
                                args.push("--mavlink-enabled".to_string()); args.push((if app.mavlink {"1"} else {"0"}).to_string());
                                args.push("--opencr-enabled".to_string()); args.push((if app.opencr {"1"} else {"0"}).to_string());
                                args.push("--outdir".to_string()); args.push("./output".to_string());
                                let _ = spawn_build(tx.clone(), args);
                            }
                        }
                        KeyCode::Char('b') => {
                            if app.building {
                                app.message = "Build already running".into();
                            } else {
                                app.message = "Starting build...".into();
                                app.output.clear();
                                app.building = true;
                                let mut args = Vec::new();
                                args.push("--profile".to_string()); args.push(app.profile.clone());
                                args.push("--machine".to_string()); args.push(app.machine.clone());
                                args.push("--image-name".to_string()); args.push(app.image_name.clone());
                                args.push("--hostname".to_string()); args.push(app.hostname_prefix.clone());
                                args.push("--robot-user".to_string()); args.push(app.robot_user.clone());
                                args.push("--robot-pass".to_string()); args.push(app.robot_pass.clone());
                                if !app.tailscale_authkey.is_empty() { args.push("--authkey".to_string()); args.push(app.tailscale_authkey.clone()); }
                                args.push("--tailscale-enabled".to_string()); args.push((if app.tailscale {"1"} else {"0"}).to_string());
                                args.push("--ros-enabled".to_string()); args.push((if app.ros {"1"} else {"0"}).to_string());
                                args.push("--mavlink-enabled".to_string()); args.push((if app.mavlink {"1"} else {"0"}).to_string());
                                args.push("--opencr-enabled".to_string()); args.push((if app.opencr {"1"} else {"0"}).to_string());
                                args.push("--outdir".to_string()); args.push("./output".to_string());
                                let _ = spawn_build(tx.clone(), args);
                                // keep in raw mode while build runs; main loop will collect output
                            }
                        }
                        KeyCode::Enter => {
                            // enter editing or selecting depending on field
                            match app.selected {
                                0 => {
                                    let opts = load_profiles();
                                    app.mode = Mode::Selecting { field: 0, options: opts, idx: 0 };
                                }
                                1 => {
                                    let opts = default_machines();
                                    app.mode = Mode::Selecting { field: 1, options: opts, idx: 0 };
                                }
                                2 => { app.mode = Mode::Editing { field: 2, buffer: app.hostname_prefix.clone() } }
                                3 => { app.mode = Mode::Editing { field: 3, buffer: app.image_name.clone() } }
                                4 => { app.mode = Mode::Editing { field: 4, buffer: app.robot_user.clone() } }
                                5 => { app.mode = Mode::Editing { field: 5, buffer: app.robot_pass.clone() } }
                                7 => { app.mode = Mode::Editing { field: 7, buffer: app.tailscale_authkey.clone() } }
                                _ => {}
                            }
                        }
                        KeyCode::Char(' ') => {
                            match app.selected {
                                6 => { app.tailscale = !app.tailscale; }
                                8 => { app.ros = !app.ros; }
                                9 => { app.mavlink = !app.mavlink; }
                                10 => { app.opencr = !app.opencr; }
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
                                0 => app.profile = val,
                                1 => app.machine = val,
                                _ => {}
                            }
                            app.mode = Mode::Normal;
                        }
                        _ => {}
                    },
                    Mode::Editing { field, buffer } => match key.code {
                        KeyCode::Esc => { app.mode = Mode::Normal; }
                        KeyCode::Enter => {
                            match *field {
                                2 => app.hostname_prefix = buffer.clone(),
                                3 => app.image_name = buffer.clone(),
                                4 => app.robot_user = buffer.clone(),
                                5 => app.robot_pass = buffer.clone(),
                                7 => app.tailscale_authkey = buffer.clone(),
                                _ => {}
                            }
                            app.mode = Mode::Normal;
                        }
                        KeyCode::Backspace => { buffer.pop(); }
                        KeyCode::Char(c) => { buffer.push(c); }
                        _ => {}
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
