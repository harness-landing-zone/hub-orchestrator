output "instance_id" {
  description = "Use with `aws ssm start-session` and with start/stop."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "The address Argo on eks-hub dials. Also the k3s cert SAN, so registration needs no insecure: true."
  value       = aws_instance.this.private_ip
}

output "cluster_endpoints" {
  description = "Server URLs for the Argo cluster Secrets, one per k3d cluster."
  value       = { for c in var.clusters : c.name => "https://${aws_instance.this.private_ip}:${c.api_port}" }
}

output "security_group_id" {
  description = "The k3d fleet SG. Extend it here if something other than the EKS nodes ever needs API access."
  value       = aws_security_group.this.id
}

output "ssm_session_command" {
  description = "How to get a shell on the box - no key pair and no public IP exist."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.this.id}"
}

output "start_command" {
  description = "The fleet is stopped on a schedule; this brings it back. The k3d-fleet unit restarts the clusters on boot."
  value       = "aws ec2 start-instances --region ${var.region} --instance-ids ${aws_instance.this.id}"
}

output "stop_command" {
  description = "Stop it yourself the moment a test finishes rather than waiting for the schedule."
  value       = "aws ec2 stop-instances --region ${var.region} --instance-ids ${aws_instance.this.id}"
}
