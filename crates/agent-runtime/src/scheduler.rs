use agent_core::{AgentRunRecord, AgentSpec, ScheduleSpec};
use time::OffsetDateTime;

pub struct AgentScheduler;

impl AgentScheduler {
    pub fn should_fire(
        &self,
        spec: &AgentSpec,
        now: OffsetDateTime,
        last_run: Option<&AgentRunRecord>,
    ) -> bool {
        match spec.schedule {
            ScheduleSpec::Manual => false,
            ScheduleSpec::Interval {
                every_seconds,
                preferred_hour_local,
                jitter_seconds,
            } => {
                if let Some(last) = last_run {
                    let elapsed = now - last.started_at;
                    if elapsed.whole_seconds() < every_seconds as i64 {
                        return false;
                    }
                }
                let Some(hour) = preferred_hour_local else {
                    return true;
                };
                let jitter = jitter_seconds.unwrap_or(300) as i64;
                let now_hour = now.hour() as i64;
                let now_minute = now.minute() as i64;
                let seconds_from_target = ((now_hour - hour as i64) * 3600 + now_minute * 60).abs();
                seconds_from_target <= jitter
            }
        }
    }
}
