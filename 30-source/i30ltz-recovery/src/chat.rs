use std::io::{BufRead, BufReader};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;

/// Spawns a background thread that handles HTTP requests to LucyServer /boltz.
/// Returns (message_sender, response_receiver) for the main thread.
pub fn spawn_chat_thread(lucy_url: String, auth_token: String) -> (Sender<String>, Receiver<String>) {
    let (req_tx, req_rx) = channel::<String>();
    let (resp_tx, resp_rx) = channel::<String>();

    thread::spawn(move || {
        let agent = ureq::AgentBuilder::new()
            .timeout(std::time::Duration::from_secs(60))
            .build();

        while let Ok(message) = req_rx.recv() {
            let url = format!("{}/boltz", lucy_url);
            let body = serde_json::json!({ "message": message });

            let result = agent
                .post(&url)
                .set("Content-Type", "application/json")
                .set("X-Swarm-Auth", &auth_token)
                .send_json(body);

            match result {
                Ok(response) => {
                    let mut full = String::new();
                    let reader = BufReader::new(response.into_reader());

                    for line in reader.lines() {
                        let line = match line {
                            Ok(l) => l,
                            Err(_) => break,
                        };

                        if let Some(data) = line.strip_prefix("data: ") {
                            if data == "[DONE]" {
                                break;
                            }
                            // Each chunk is raw text with \n escaped as literal \\n
                            let chunk = data.replace("\\n", "\n");
                            full.push_str(&chunk);
                        }
                    }

                    let out = if full.trim().is_empty() {
                        "No response.".to_string()
                    } else {
                        full
                    };
                    resp_tx.send(out).ok();
                }
                Err(ureq::Error::Status(code, _)) => {
                    resp_tx
                        .send(format!("[HTTP {}] LucyServer returned an error.", code))
                        .ok();
                }
                Err(e) => {
                    resp_tx
                        .send(format!(
                            "[OFFLINE] Cannot reach LucyServer.\n\nRun lucy-server or check LUCY_URL.\n\nDetail: {}",
                            e
                        ))
                        .ok();
                }
            }
        }
    });

    (req_tx, resp_rx)
}
