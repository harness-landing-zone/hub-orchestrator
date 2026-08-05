################################################################################
# Scheduled stop
#
# The cost guard for the run that gets forgotten. It STOPS, never terminates:
# the k3d-fleet systemd unit brings all three clusters back on the next start,
# so a stop costs the time to boot, not the fleet.
#
# EventBridge Scheduler's universal target calls the EC2 API directly, so there
# is no Lambda to own, patch, or debug.
################################################################################

data "aws_iam_policy_document" "scheduler_assume" {
  count = var.auto_stop_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler" {
  count = var.auto_stop_enabled ? 1 : 0

  statement {
    actions   = ["ec2:StopInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "scheduler" {
  count = var.auto_stop_enabled ? 1 : 0

  name               = "${var.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.auto_stop_enabled ? 1 : 0

  name   = "stop-instances"
  role   = aws_iam_role.scheduler[0].id
  policy = data.aws_iam_policy_document.scheduler[0].json
}

resource "aws_scheduler_schedule" "stop" {
  count = var.auto_stop_enabled ? 1 : 0

  name        = "${var.name}-stop"
  description = "Stop the k3d test fleet so a forgotten run cannot bill overnight"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.auto_stop_cron
  schedule_expression_timezone = var.auto_stop_timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.this.id]
    })
  }
}
