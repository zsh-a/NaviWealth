use super::*;

pub(super) fn remove_node_form(id: String, purpose: bool, node: String) -> AnyElement {
    tree_form(id, move |p| {
        let source_portfolio = p
            .data
            .portfolios
            .iter()
            .find(|p| {
                if purpose {
                    p.id == node
                } else {
                    p.sleeves.iter().any(|s| s.id == node)
                }
            })
            .cloned();
        let Some(source) = source_portfolio else {
            return error_page();
        };
        let choices = p
            .data
            .portfolios
            .iter()
            .filter(|p| {
                if purpose {
                    p.id != node
                } else {
                    p.id == source.id
                }
            })
            .flat_map(|p| {
                p.sleeves
                    .iter()
                    .filter(|s| purpose || s.id != node)
                    .map(|s| (s.id.clone(), format!("{} / {}", p.name, s.name)))
            })
            .collect::<Vec<_>>();
        let node = node.clone();
        fui::form(
            if purpose {
                "移除投资用途"
            } else {
                "移除资本策略"
            },
            vec![
                fui::Field::choice("receiver", "接收资本的策略", "", choices)
                    .help("源配置的目标份额与纳入资产一起转移；真实账户、持仓及成交不会改写。"),
                fui::Field::choice(
                    "confirm",
                    "确认处理",
                    "keep",
                    vec![
                        ("keep".into(), "保留当前配置".into()),
                        ("remove".into(), "移除并转移资本".into()),
                    ],
                ),
            ],
            move |v| {
                let mut data = p.data.clone();
                let id = p.id.clone();
                let node = node.clone();
                Box::pin(async move {
                    if fui::value(&v, "confirm") != "remove" {
                        return Err("请选择移除并转移，或返回保留配置".into());
                    }
                    let receiver = fui::required(&v, "receiver", "接收策略")?;
                    let receiver_portfolio = data
                        .portfolios
                        .iter()
                        .find(|p| p.sleeves.iter().any(|s| s.id == receiver))
                        .map(|p| p.id.clone())
                        .ok_or("接收策略不存在")?;
                    if purpose {
                        if receiver_portfolio == node || data.portfolios.len() < 2 {
                            return Err("必须保留至少一个投资用途".into());
                        }
                        let index = data
                            .portfolios
                            .iter()
                            .position(|p| p.id == node)
                            .ok_or("源用途不存在")?;
                        let removed = data.portfolios.remove(index);
                        let receiving = data
                            .portfolios
                            .iter_mut()
                            .find(|p| p.id == receiver_portfolio)
                            .ok_or("接收用途不存在")?;
                        receiving.target_bps = receiving
                            .target_bps
                            .checked_add(removed.target_bps)
                            .ok_or("目标份额超出范围")?;
                        for i in &mut data.inclusions {
                            if i.portfolio_id == node {
                                i.portfolio_id = receiver_portfolio.clone();
                                i.sleeve_id = receiver.clone();
                            }
                        }
                    } else {
                        let portfolio = data
                            .portfolios
                            .iter_mut()
                            .find(|p| p.sleeves.iter().any(|s| s.id == node))
                            .ok_or("源策略不存在")?;
                        if portfolio.id != receiver_portfolio || portfolio.sleeves.len() < 2 {
                            return Err("接收策略须与源策略同属一个用途，且至少保留一个策略".into());
                        }
                        let index = portfolio
                            .sleeves
                            .iter()
                            .position(|s| s.id == node)
                            .ok_or("源策略不存在")?;
                        let removed = portfolio.sleeves.remove(index);
                        let receiving = portfolio
                            .sleeves
                            .iter_mut()
                            .find(|s| s.id == receiver)
                            .ok_or("接收策略不存在")?;
                        receiving.target_bps = receiving
                            .target_bps
                            .checked_add(removed.target_bps)
                            .ok_or("目标份额超出范围")?;
                        for i in &mut data.inclusions {
                            if i.sleeve_id == node {
                                i.sleeve_id = receiver.clone();
                            }
                        }
                    }
                    fui::services()
                        .save_finance_portfolio_plan(Some(id.clone()), data, today())
                        .await?;
                    Ok(Some(format!("/wealth/portfolios/{id}")))
                })
            },
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_sibling_weights_stay_exact() {
        assert_eq!(
            redistribute(&[5000, 3000, 2000], 0, 4000).unwrap(),
            vec![4000, 3600, 2400]
        );
        assert_eq!(
            redistribute(&[10000, 0], 1, 3333).unwrap(),
            vec![6667, 3333]
        );
        assert_eq!(
            redistribute(&[0, 0, 10000], 2, 0).unwrap(),
            vec![5000, 5000, 0]
        );
        assert!(redistribute(&[10000], 0, 5000).is_err());
    }
}
