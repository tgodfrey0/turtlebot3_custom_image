use std::error::Error;
use std::io::{self, Write, BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode};
use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Alignment, Constraint, Direction, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Span, Spans};
use ratatui::widgets::{Block, Borders, Clear, Gauge, List, ListItem, Paragraph};
use ratatui::Terminal;

enum Mode {
    Normal,
    Editing { field: usize, buffer: String },
    Selecting { field: usize, options: Vec<String>, idx: usize },
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
    spinner: usize,
    profiles: Vec<String>,
    machines: Vec<String>,
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
            spinner: 0,
            profiles,
            machines,
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

fn run_build_sh(args: &Vec<String>) -> Result<i32, Box<dyn Error>> {
    if let Some(build) = find_build_sh() {
        let mut cmd = Command::new(build);
        for a in args.iter() { cmd.arg(a); }
        let status = cmd.status()?;
        Ok(status.code().unwrap_or(0))
    } else {
        Err("build.sh not found".into())
    }
}

fn main() -> Result<(), Box<dyn Error>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App::default();
    let tick_rate = Duration::from_millis(200);
    let mut last_tick = Instant::now();

    loop {
        terminal.draw(|f| {
            let size = f.size();
            // draw grey background
            let bg = Paragraph::new("").block(Block::default().style(Style::default().bg(Color::Rgb(128,128,128))));
            f.render_widget(bg, size);

            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Percentage(65), Constraint::Percentage(35)].as_ref())
                .split(size);

            let left_chunks = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(50), Constraint::Percentage(50)].as_ref())
                .split(chunks[0]);

            let items: Vec<ListItem> = app.items.iter().enumerate().map(|(i, it)| {
                let val = match i {
                    0 => format!("{}: {}", it, app.profile),
                    1 => format!("{}: {}", it, app.machine),
                    2 => format!("{}: {}", it, app.hostname_prefix),
                    3 => format!("{}: {}", it, app.image_name),
                    4 => format!("{}: {}", it, app.robot_user),
                    5 => format!("{}: {}", it, "****"),
                    6 => format!("{}: {}", it, if app.tailscale {"enabled"} else {"disabled"}),
                    7 => format!("{}: {}", it, if app.tailscale_authkey.is_empty() {"(none)"} else {"(set)"}),
                    8 => format!("{}: {}", it, if app.ros {"enabled"} else {"disabled"}),
                    9 => format!("{}: {}", it, if app.mavlink {"enabled"} else {"disabled"}),
                    10 => format!("{}: {}", it, if app.opencr {"enabled"} else {"disabled"}),
                    11 => format!("Actions: p=preview e=export b=build q=quit"),
                    _ => it.clone(),
                };
                ListItem::new(Spans::from(Span::raw(val)))
            }).collect();

            let mut state = ratatui::widgets::ListState::default();
            state.select(Some(app.selected));
            let list = List::new(items).block(Block::default().borders(Borders::ALL).title("Build Options")).highlight_style(Style::default().bg(Color::Yellow).fg(Color::Black).add_modifier(Modifier::BOLD));
            f.render_stateful_widget(list, left_chunks[0], &mut state);

            let preview = Paragraph::new(Spans::from(vec![Span::raw(format!("Preview command: ./build.sh --profile {} --machine {}\n", app.profile, app.machine)), Span::raw(format!("Message: {}", app.message))]))
                .block(Block::default().borders(Borders::ALL).title("Preview"));
            f.render_widget(preview, left_chunks[1]);

            // bottom output area is chunks[1]
            let out_lines: Vec<Span> = app.output.iter().rev().take((chunks[1].height as usize - 2)).rev().map(|l| Span::raw(l.clone())).collect();
            let output_para = Paragraph::new(Spans::from(out_lines)).block(Block::default().borders(Borders::ALL).title(if app.building {"Output (building)..."} else {"Output"}));
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
                            app.message = "Running preview...".into();
                            disable_raw_mode().ok();
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
                            match run_build_sh(&args) { Ok(code) => app.message = format!("Preview finished (exit {}). See conf/local.conf", code), Err(e) => app.message = format!("Preview failed: {}", e), }
                            enable_raw_mode().ok();
                        }
                        KeyCode::Char('e') => {
                            app.message = "Exporting conf (no build)...".into();
                            disable_raw_mode().ok();
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
                            match run_build_sh(&args) { Ok(code) => app.message = format!("Export finished (exit {})", code), Err(e) => app.message = format!("Export failed: {}", e), }
                            enable_raw_mode().ok();
                        }
                        KeyCode::Char('b') => {
                            app.message = "Running build (this may take long)...".into();
                            disable_raw_mode().ok();
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
                            match run_build_sh(&args) { Ok(code) => app.message = format!("Build finished (exit {})", code), Err(e) => app.message = format!("Build failed: {}", e), }
                            enable_raw_mode().ok();
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
