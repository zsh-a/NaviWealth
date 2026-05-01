use argon2::password_hash::SaltString;
use argon2::{Argon2, PasswordHasher};
use std::env;
use std::path::PathBuf;
use std::process::Command;
use uuid::Uuid;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.iter().any(|a| a == "--help" || a == "-h") {
        print_usage();
        return;
    }

    let email = get_arg(&args, "--email").unwrap_or_else(|| {
        eprintln!("Error: --email is required");
        print_usage();
        std::process::exit(1);
    });

    let execute = args.iter().any(|a| a == "--execute");
    let password = get_arg(&args, "--password").unwrap_or_else(|| {
        rpassword::prompt_password("Password: ").expect("Failed to read password")
    });

    if password.len() < 8 {
        eprintln!("Error: password must be at least 8 characters");
        std::process::exit(1);
    }

    let user_id = Uuid::new_v4().to_string();
    let email_normalized = email.trim().to_ascii_lowercase();
    let password_hash = hash_password(&password);

    println!("\n-- Generated user registration");
    println!("-- Email: {}", email_normalized);
    println!("-- User ID: {}", user_id);
    println!();
    println!(
        "INSERT INTO users (id, email, password_hash) VALUES ('{}', '{}', '{}');",
        user_id, email_normalized, password_hash
    );

    if execute {
        let backend_dir = find_backend_dir();
        let sql = format!(
            "INSERT INTO users (id, email, password_hash) VALUES ('{}', '{}', '{}');",
            user_id, email_normalized, password_hash
        );
        println!(
            "\nExecuting against D1 (from {})...",
            backend_dir.display()
        );
        let status = Command::new("wrangler")
            .args(["d1", "execute", "naviwealth", "--remote", "--command", &sql])
            .current_dir(&backend_dir)
            .status()
            .expect("Failed to run wrangler. Is it installed?");
        if status.success() {
            println!("User registered successfully.");
        } else {
            eprintln!("wrangler exited with {}", status);
            std::process::exit(1);
        }
    } else {
        println!("\nTo execute against D1, re-run with --execute");
    }
}

/// Resolve apps/backend/ relative to this binary's location.
/// Binary is at tool/register-user/target/release/register-user,
/// so backend is ../../../apps/backend/.
fn find_backend_dir() -> PathBuf {
    let exe = env::current_exe().expect("Failed to determine executable path");
    let root = exe
        .parent()        // release/
        .and_then(|p| p.parent())  // target/
        .and_then(|p| p.parent())  // register-user/
        .and_then(|p| p.parent())  // tool/
        .and_then(|p| p.parent()); // project root
    match root {
        Some(r) => {
            let backend = r.join("apps").join("backend");
            if !backend.join("wrangler.toml").exists() {
                eprintln!(
                    "Error: expected wrangler.toml at {}",
                    backend.display()
                );
                std::process::exit(1);
            }
            backend
        }
        None => {
            eprintln!("Error: could not resolve project root from executable path");
            std::process::exit(1);
        }
    }
}

fn hash_password(password: &str) -> String {
    let mut salt_bytes = [0u8; 16];
    getrandom::getrandom(&mut salt_bytes).expect("Failed to generate random salt");
    let salt = SaltString::encode_b64(&salt_bytes).expect("Failed to encode salt");
    let argon2 = Argon2::default();
    argon2
        .hash_password(password.as_bytes(), &salt)
        .expect("Failed to hash password")
        .to_string()
}

fn get_arg(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn print_usage() {
    eprintln!(
        "Usage: register-user --email <EMAIL> [--password <PASSWORD>] [--execute]

Options:
  --email <EMAIL>          User email (required)
  --password <PASSWORD>    Password (prompted interactively if omitted)
  --execute                Run the INSERT against D1 via wrangler
  -h, --help               Show this help"
    );
}
