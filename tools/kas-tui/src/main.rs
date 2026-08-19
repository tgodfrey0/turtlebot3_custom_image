use std::error::Error;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant};

use crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode};
use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Span, Spans};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph};
use ratatui::Terminal;

struct App {
    items: Vec<String>,
    selected: usize,

    // fields
    profile: String,
    machine: String,
    hostname_prefix: String,
    image_name: String,
    tailscale: bool,
    tailscale_authkey: String,
    ros: bool,
    mavlink: bool,
    opencr: bool,

    message: String,
}

impl Default for App {
    fn default() -> Self {
        Self {
            items: vec![
                "Profile".into(),
                "Machine".into(),
                "Hostname prefix".into(),
                "Image name".into(),
                "Tailscale".into(),
                "Tailscale authkey".into(),
                "ROS2".into(),
                "MAVLink".into(),
                "OpenCR".into(),
                "Actions".into(),
            ],
            selected: 0,
            profile: "generic".into(),
            machine: "raspberrypi4-64".into(),
            hostname_prefix: "robot".into(),
            image_name: "uav_companion".into(),
            tailscale: true,
            tailscale_authkey: "".into(),
            ros: false,
            mavlink: false,
            opencr: false,
            message: "Press Enter to edit, Space to toggle, p=preview, e=export, b=build, q=quit".into(),
        }
    }
}

fn find_build_sh() -> Option<PathBuf> {
    // search current dir and up to 6 parents for build.sh
    if let Ok(mut dir) = std::env::current_dir() {
        for _ in 0..6 {
            let candidate = dir.join("build.sh");
            if candidate.exists() {
                return Some(candidate);
            }
            if !dir.pop() {
                break;
            }
        }
    }
    None
}

fn run_build_sh(args: &[&str]) -> Result<i32, Box<dyn Error>> {
    if let Some(build) = find_build_sh() {
        let mut cmd = Command::new(build);
        for a in args { cmd.arg(a); }
        let status = cmd.status()?;
        Ok(status.code().unwrap_or(0))
    } else {
        Err("build.sh not found in current or parent dirs".into())
    }
}

fn prompt_input(prompt: &str, initial: &str) -> io::Result<String> {
    // disable raw mode to read a full line
    disable_raw_mode().ok();
    execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture).ok();
    print!("{} [{}]: ", prompt, initial);
    io::stdout().flush()?;
    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    // restore alternate screen will be handled by caller
    let v = input.trim().to_string();
    if v.is_empty() {
        Ok(initial.to_string())
    } else {
        Ok(v)
    }
}

fn main() -> Result<(), Box<dyn Error>> {
    // Setup terminal
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
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Percentage(70), Constraint::Percentage(30)].as_ref())
                .split(size);

            let left_chunks = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(50), Constraint::Percentage(50)].as_ref())
                .split(chunks[0]);

            // left: settings list
            let items: Vec<ListItem> = app
                .items
                .iter()
                .enumerate()
                .map(|(i, it)| {
                    let val = match i {
                        0 => format!("{}: {}", it, app.profile),
                        1 => format!("{}: {}", it, app.machine),
                        2 => format!("{}: {}", it, app.hostname_prefix),
                        3 => format!("{}: {}", it, app.image_name),
                        4 => format!("{}: {}", it, if app.tailscale {"enabled"} else {"disabled"}),
                        5 => format!("{}: {}", it, app.tailscale_authkey),
                        6 => format!("{}: {}", it, if app.ros {"enabled"} else {"disabled"}),
                        7 => format!("{}: {}", it, if app.mavlink {"enabled"} else {"disabled"}),
                        8 => format!("{}: {}", it, if app.opencr {"enabled"} else {"disabled"}),
                        9 => format!("Actions: p=preview e=export b=build q=quit"),
                        _ => it.clone(),
                    };
                    ListItem::new(Spans::from(Span::raw(val)))
                })
                .collect();

            let list = List::new(items)
                .block(Block::default().borders(Borders::ALL).title("Build Options"))
                .highlight_style(Style::default().bg(Color::Blue).fg(Color::White).add_modifier(Modifier::BOLD));

            f.render_stateful_widget(list, left_chunks[0], &mut {
                let mut s = ratatui::widgets::ListState::default();
                s.select(Some(app.selected));
                s
            });

            // right: preview area
            let preview = Paragraph::new(Spans::from(vec![Span::raw(format!("Preview command: ./build.sh --profile {} --machine {}\n\nMessage: {}", app.profile, app.machine, app.message))]))
                .block(Block::default().borders(Borders::ALL).title("Preview"));
            f.render_widget(preview, left_chunks[1]);

            // bottom: help/log
            let help = Paragraph::new(Spans::from(vec![Span::raw(&app.message)])).block(Block::default().borders(Borders::ALL).title("Status"));
            f.render_widget(help, chunks[1]);
        })?;

        let timeout = tick_rate
            .checked_sub(last_tick.elapsed())
            .unwrap_or_else(|| Duration::from_secs(0));

        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                match key.code {
                    KeyCode::Char('q') => break,
                    KeyCode::Down => {
                        app.selected = (app.selected + 1) % app.items.len();
                    }
                    KeyCode::Up => {
                        if app.selected == 0 { app.selected = app.items.len() - 1; } else { app.selected -= 1; }
                    }
                    KeyCode::Char('p') => {
                        app.message = "Running preview...".into();
                        disable_raw_mode().ok();
                        // call build.sh --profile X --dry-run
                        let args = ["--profile", &app.profile, "--machine", &app.machine, "--dry-run"];
                        match run_build_sh(&args) {
                            Ok(code) => app.message = format!("Preview finished (exit {}). See conf/local.conf", code),
                            Err(e) => app.message = format!("Preview failed: {}", e),
                        }
                        enable_raw_mode().ok();
                    }
                    KeyCode::Char('e') => {
                        app.message = "Exporting conf (no build)...".into();
                        disable_raw_mode().ok();
                        let mut args = vec!["--profile", &app.profile, "--no-build"];
                        args.push("--machine"); args.push(&app.machine);
                        if app.tailscale && !app.tailscale_authkey.is_empty() {
                            args.push("--authkey"); args.push(&app.tailscale_authkey);
                        }
                        match run_build_sh(&args) {
                            Ok(code) => app.message = format!("Export finished (exit {})", code),
                            Err(e) => app.message = format!("Export failed: {}", e),
                        }
                        enable_raw_mode().ok();
                    }
                    KeyCode::Char('b') => {
                        app.message = "Running build (this may take long)...".into();
                        disable_raw_mode().ok();
                        let mut args = vec!["--profile", &app.profile];
                        args.push("--machine"); args.push(&app.machine);
                        if app.tailscale && !app.tailscale_authkey.is_empty() {
                            args.push("--authkey"); args.push(&app.tailscale_authkey);
                        }
                        match run_build_sh(&args) {
                            Ok(code) => app.message = format!("Build finished (exit {})", code),
                            Err(e) => app.message = format!("Build failed: {}", e),
                        }
                        enable_raw_mode().ok();
                    }
                    KeyCode::Enter => {
                        // edit selected field
                        match app.selected {
                            0 => {
                                // profile
                                app.message = "Enter profile (generic/turtlebot3)".into();
                                let v = prompt_input("Profile", &app.profile).unwrap_or(app.profile.clone());
                                app.profile = v;
                            }
                            1 => {
                                app.message = "Enter machine".into();
                                let v = prompt_input("Machine", &app.machine).unwrap_or(app.machine.clone());
                                app.machine = v;
                            }
                            2 => {
                                app.message = "Enter hostname prefix".into();
                                let v = prompt_input("Hostname prefix", &app.hostname_prefix).unwrap_or(app.hostname_prefix.clone());
                                app.hostname_prefix = v;
                            }
                            3 => {
                                app.message = "Enter image name".into();
                                let v = prompt_input("Image name", &app.image_name).unwrap_or(app.image_name.clone());
                                app.image_name = v;
                            }
                            5 => {
                                app.message = "Enter tailscale authkey (leave empty for manual)".into();
                                let v = prompt_input("Tailscale authkey", &app.tailscale_authkey).unwrap_or(app.tailscale_authkey.clone());
                                app.tailscale_authkey = v;
                            }
                            _ => {
                                // other fields are toggles
                            }
                        }
                    }
                    KeyCode::Char(' ') => {
                        // toggle booleans
                        match app.selected {
                            4 => { app.tailscale = !app.tailscale; }
                            6 => { app.ros = !app.ros; }
                            7 => { app.mavlink = !app.mavlink; }
                            8 => { app.opencr = !app.opencr; }
                            _ => {}
                        }
                    }
                    _ => {}
                }
            }
        }

        if last_tick.elapsed() >= tick_rate {
            last_tick = Instant::now();
        }
    }

    // restore terminal
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen, DisableMouseCapture)?;
    terminal.show_cursor()?;

    Ok(())
}
