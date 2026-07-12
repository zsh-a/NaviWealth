pub const DOMAIN_PREFIXES: &[(&str, &str)] = &[
    ("fin:", "finance"),
    ("health:", "health"),
    ("know:", "knowledge"),
    ("exec:", "execution"),
];

pub fn domain_for_wire_table(table: &str) -> Option<&'static str> {
    DOMAIN_PREFIXES
        .iter()
        .find_map(|(prefix, domain)| table.starts_with(prefix).then_some(*domain))
}

pub fn prefix_for_domain(domain: &str) -> Option<&'static str> {
    DOMAIN_PREFIXES
        .iter()
        .find_map(|(prefix, candidate)| (*candidate == domain).then_some(*prefix))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_production_domains_round_trip() {
        for (prefix, domain) in DOMAIN_PREFIXES {
            assert_eq!(prefix_for_domain(domain), Some(*prefix));
            assert_eq!(
                domain_for_wire_table(&format!("{prefix}rows")),
                Some(*domain)
            );
        }
    }

    #[test]
    fn execution_prefix_is_registered() {
        assert_eq!(
            domain_for_wire_table("exec:execution_actions"),
            Some("execution")
        );
    }
}
