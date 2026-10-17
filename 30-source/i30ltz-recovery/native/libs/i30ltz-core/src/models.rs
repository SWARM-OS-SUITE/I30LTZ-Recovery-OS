//! Shared domain models — Case, Drive, DiagReport, etc.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ── Recovery Case ──────────────────────────────────────────────────────────
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoveryCase {
    pub id: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub client: String,
    pub device: String,
    pub status: CaseStatus,
    pub priority: Priority,
    pub notes: Vec<String>,
    pub drives: Vec<DriveInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CaseStatus {
    Open,
    Triaging,
    Imaging,
    Analyzing,
    Recovering,
    Completed,
    Failed,
    Archived,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum Priority {
    Low,
    Normal,
    High,
    Critical,
}

// ── Drive Info ─────────────────────────────────────────────────────────────
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriveInfo {
    pub device: String, // e.g. /dev/sda
    pub model: String,
    pub serial: String,
    pub size_bytes: u64,
    pub health: DriveHealth,
    pub smart: Option<SmartData>,
    pub scanned_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum DriveHealth {
    Healthy,
    Warning,
    Critical,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmartData {
    pub reallocated_sectors: u64,
    pub pending_sectors: u64,
    pub uncorrectable: u64,
    pub power_on_hours: u64,
    pub temperature_c: i32,
    pub overall: DriveHealth,
}

// ── Diagnostic Report ──────────────────────────────────────────────────────
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiagReport {
    pub case_id: Uuid,
    pub generated: DateTime<Utc>,
    pub summary: String,
    pub findings: Vec<Finding>,
    pub recommended: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Finding {
    pub severity: Priority,
    pub category: String,
    pub message: String,
}
