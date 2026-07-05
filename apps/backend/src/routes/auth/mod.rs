mod handlers;
mod models;
mod session;

pub use handlers::{list_devices, login, logout, refresh, register};

#[cfg(test)]
mod tests {
    use super::session::normalise_domains;

    #[test]
    fn normalise_domains_keeps_finance_and_curated_optional_domains() {
        let domains = normalise_domains(vec![
            "knowledge".to_string(),
            "time".to_string(),
            "health".to_string(),
            "health".to_string(),
        ]);
        assert_eq!(
            domains,
            vec![
                "finance".to_string(),
                "health".to_string(),
                "knowledge".to_string()
            ]
        );
    }
}
