use std::fs;
use std::process::Command;

#[derive(Default, Clone)]
pub struct EvalData {
    // System
    pub hostname: String,
    pub uptime: String,
    pub cpu_model: String,
    pub cpu_count: u32,
    pub ram_total_mb: u64,
    pub ram_avail_mb: u64,
    pub ram_used_pct: u8,
    pub load_1: f32,
    pub load_5: f32,
    pub load_15: f32,
    pub cpu_temp: String,
    // Boot
    pub boot_time: String,
    pub failed_units: Vec<String>,
    // Disk
    pub mounts: Vec<DiskMount>,
    // Services
    pub services: Vec<ServiceInfo>,
}

#[derive(Clone)]
pub struct DiskMount {
    pub target: String,
    pub source: String,
    pub size: String,
    pub used: String,
    pub avail: String,
    pub pct: u8,
}

#[derive(Clone)]
pub struct ServiceInfo {
    pub name: String,
    pub active: bool,
}

pub fn collect_all() -> EvalData {
    let mut d = EvalData::default();

    // Hostname
    d.hostname = fs::read_to_string("/etc/hostname")
        .unwrap_or_default()
        .trim()
        .to_string();
    if d.hostname.is_empty() {
        d.hostname = "unknown".to_string();
    }

    // Uptime
    if let Ok(s) = fs::read_to_string("/proc/uptime") {
        let secs = s.split_whitespace()
            .next()
            .and_then(|x| x.parse::<f64>().ok())
            .unwrap_or(0.0);
        let h = (secs / 3600.0) as u64;
        let m = ((secs % 3600.0) / 60.0) as u64;
        let sec = (secs % 60.0) as u64;
        d.uptime = format!("{}h {}m {}s", h, m, sec);
    }

    // CPU info
    if let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") {
        for line in cpuinfo.lines() {
            if line.starts_with("model name") && d.cpu_model.is_empty() {
                d.cpu_model = line
                    .splitn(2, ':')
                    .nth(1)
                    .unwrap_or("Unknown")
                    .trim()
                    .to_string();
            }
            if line.starts_with("processor") {
                d.cpu_count += 1;
            }
        }
    }
    if d.cpu_model.is_empty() {
        d.cpu_model = "Unknown CPU".to_string();
    }

    // Memory
    if let Ok(mem) = fs::read_to_string("/proc/meminfo") {
        for line in mem.lines() {
            if line.starts_with("MemTotal:") {
                d.ram_total_mb = parse_kb(line) / 1024;
            } else if line.starts_with("MemAvailable:") {
                d.ram_avail_mb = parse_kb(line) / 1024;
            }
        }
        if d.ram_total_mb > 0 {
            let used = d.ram_total_mb - d.ram_avail_mb;
            d.ram_used_pct = ((used * 100) / d.ram_total_mb) as u8;
        }
    }

    // Load averages
    if let Ok(la) = fs::read_to_string("/proc/loadavg") {
        let parts: Vec<&str> = la.split_whitespace().collect();
        d.load_1 = parts.first().and_then(|x| x.parse().ok()).unwrap_or(0.0);
        d.load_5 = parts.get(1).and_then(|x| x.parse().ok()).unwrap_or(0.0);
        d.load_15 = parts.get(2).and_then(|x| x.parse().ok()).unwrap_or(0.0);
    }

    // CPU temperature (first thermal zone)
    if let Ok(t) = fs::read_to_string("/sys/class/thermal/thermal_zone0/temp") {
        if let Ok(millideg) = t.trim().parse::<f32>() {
            d.cpu_temp = format!("{:.1}°C", millideg / 1000.0);
        }
    }
    if d.cpu_temp.is_empty() {
        d.cpu_temp = "N/A".to_string();
    }

    // Boot time (systemd-analyze)
    if let Ok(out) = Command::new("systemd-analyze").output() {
        if let Ok(s) = String::from_utf8(out.stdout) {
            d.boot_time = s.lines().next().unwrap_or("unavailable").trim().to_string();
        }
    }
    if d.boot_time.is_empty() {
        d.boot_time = "systemd-analyze unavailable".to_string();
    }

    // Failed units
    if let Ok(out) = Command::new("systemctl")
        .args(["list-units", "--state=failed", "--no-legend", "--plain"])
        .output()
    {
        if let Ok(s) = String::from_utf8(out.stdout) {
            d.failed_units = s
                .lines()
                .filter(|l| !l.trim().is_empty())
                .map(|l| {
                    l.split_whitespace()
                        .next()
                        .unwrap_or(l)
                        .to_string()
                })
                .collect();
        }
    }

    // Disk mounts (exclude tmpfs / devtmpfs)
    if let Ok(out) = Command::new("df")
        .args(["-h", "--output=source,size,used,avail,pcent,target"])
        .output()
    {
        if let Ok(s) = String::from_utf8(out.stdout) {
            for line in s.lines().skip(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() < 6 {
                    continue;
                }
                let src = parts[0];
                if src == "tmpfs" || src == "devtmpfs" || src.starts_with("efivar") {
                    continue;
                }
                let pct = parts[4].trim_end_matches('%').parse().unwrap_or(0u8);
                d.mounts.push(DiskMount {
                    source: src.to_string(),
                    size: parts[1].to_string(),
                    used: parts[2].to_string(),
                    avail: parts[3].to_string(),
                    pct,
                    target: parts[5].to_string(),
                });
            }
        }
    }

    // Key services
    let services = [
        "lucy-server",
        "gaming-agent",
        "google-workspace",
        "swarm-ui",
        "NetworkManager",
        "sshd",
        "bluetooth",
        "firewalld",
    ];
    for name in &services {
        let active = Command::new("systemctl")
            .args(["is-active", "--quiet", name])
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        d.services.push(ServiceInfo {
            name: name.to_string(),
            active,
        });
    }

    d
}

fn parse_kb(line: &str) -> u64 {
    line.split_whitespace()
        .nth(1)
        .and_then(|x| x.parse().ok())
        .unwrap_or(0)
}
