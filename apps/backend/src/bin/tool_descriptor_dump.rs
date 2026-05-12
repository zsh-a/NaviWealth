fn main() -> Result<(), Box<dyn std::error::Error>> {
    let registry = naviwealth_backend::ai::tools::registry();
    let descriptors = registry.descriptors();
    println!("{}", serde_json::to_string_pretty(&descriptors)?);
    Ok(())
}
