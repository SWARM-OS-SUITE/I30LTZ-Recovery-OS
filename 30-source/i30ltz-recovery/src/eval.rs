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
    // Drives (lsblk) and the local AI engine
    pub drives: Vec<Drive>,
    pub ollama_up: bool,
}

#[derive(Clone, Default)]
pub struct Drive {
    pub name: String, // sda, nvme0n1
    pub model: String,
    pub serial: String,
    pub tran: String, // sata, nvme, usb
    pub size: u64,
    pub rotational: bool,
    pub read_only: bool,
    pub parts: Vec<Part>,
}

#[derive(Clone, Default)]
pub struct Part {
    pub name: String,
    pub size: u64,
    pub fstype: String,
    pub label: String,
    pub mountpoint: String,
}

impl Drive {
    pub fn kind(&self) -> &'static str {
        if self.tran == "nvme" {
            "NVMe SSD"
        } else if self.tran == "usb" {
            "External" // USB bridges often report a wrong rotational flag
        } else if self.rotational {
            "HDD"
        } else {
            "SSD"
        }
    }
}

pub fn human_size(b: u64) -> String {
    const U: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut v = b as f64;
    let mut i = 0;
    while v >= 1000.0 && i < 4 {
        v /= 1000.0;
        i += 1;
    }
    if i == 0 { format!("{b} B") } else { format!("{:.1} {}", v, U[i]) }
}

fn jstr(v: &serde_json::Value, k: &str) -> String {
    v.get(k).and_then(|x| x.as_str()).unwrap_or("").trim().to_string()
}
fn jnum(v: &serde_json::Value, k: &str) -> u64 {
    match v.get(k) {
        Some(x) if x.is_u64() => x.as_u64().unwrap_or(0),
        Some(x) => x.as_str().and_then(|s| s.parse().ok()).unwrap_or(0),
        None => 0,
    }
}
fn jbool(v: &serde_json::Value, k: &str) -> bool {
    match v.get(k) {
        Some(x) if x.is_boolean() => x.as_bool().unwrap_or(false),
        Some(x) => matches!(x.as_str(), Some("1") | Some("true")) || x.as_u64() == Some(1),
        None => false,
    }
}

/// Physical disks and their partitions from `lsblk -J` (no root needed). Loop/ram/optical devices are skipped.
pub fn collect_drives() -> Vec<Drive> {
    let out = match Command::new("lsblk")
        .args(["-J", "-b", "-o", "NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL,TRAN,ROTA,RO"])
        .output()
    {
        Ok(o) => o,
        Err(_) => return Vec::new(),
    };
    let v: serde_json::Value = match serde_json::from_slice(&out.stdout) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };
    let mut drives = Vec::new();
    for dev in v.get("blockdevices").and_then(|b| b.as_array()).cloned().unwrap_or_default() {
        if jstr(&dev, "type") != "disk" {
            continue;
        }
        let mut dr = Drive {
            name: jstr(&dev, "name"),
            model: jstr(&dev, "model"),
            serial: jstr(&dev, "serial"),
            tran: jstr(&dev, "tran"),
            size: jnum(&dev, "size"),
            rotational: jbool(&dev, "rota"),
            read_only: jbool(&dev, "ro"),
            parts: Vec::new(),
        };
        if dr.name.starts_with("zram") || dr.name.starts_with("ram") {
            continue;
        }
        for ch in dev.get("children").and_then(|c| c.as_array()).cloned().unwrap_or_default() {
            dr.parts.push(Part {
                name: jstr(&ch, "name"),
                size: jnum(&ch, "size"),
                fstype: jstr(&ch, "fstype"),
                label: jstr(&ch, "label"),
                mountpoint: jstr(&ch, "mountpoint"),
            });
        }
        drives.push(dr);
    }
    drives
}

/// True when the local Ollama answers on 127.0.0.1:11434 (the MAD AI engine).
pub fn ollama_up() -> bool {
    use std::net::{SocketAddr, TcpStream};
    use std::time::Duration;
    let addr: SocketAddr = "127.0.0.1:11434".parse().unwrap();
    TcpStream::connect_timeout(&addr, Duration::from_millis(150)).is_ok()
}

/// SMART overall health for one disk: "PASSED", "FAILED" or "n/a" (smartctl missing or no permission).
pub fn smart_health(dev: &str) -> String {
    let path = format!("/dev/{dev}");
    for cmd in [vec!["smartctl", "-H", &path], vec!["sudo", "-n", "smartctl", "-H", &path]] {
        if let Ok(o) = Command::new(cmd[0]).args(&cmd[1..]).output() {
            let t = String::from_utf8_lossy(&o.stdout).to_string();
            if t.contains("PASSED") || t.contains("Health Status: OK") {
                return "PASSED".into();
            }
            if t.contains("FAILED") {
                return "FAILED".into();
            }
        }
    }
    "n/a".into()
}

#[derive(Clone)]
#[allow(dead_code)]
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
    d.drives = collect_drives();
    d.ollama_up = ollama_up();

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
    // Recovery OS services (MAD AI engine + brain, network, remote access, firewall, disk automounting)
    let services = [
        "ollama",
        "mad-dr-boltz",
        "NetworkManager",
        "nftables",
        "tailscaled",
        "sshd",
        "udisks2",
        "bluetooth",
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
