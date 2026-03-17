###############################################################################
# Monitoring Module Outputs
###############################################################################

output "workspace_resource_id" {
  description = "Azure resource ID of the Log Analytics Workspace. Use this when configuring diagnostic settings on other resources."
  value       = module.log_analytics_workspace.resource_id
}

output "workspace_id" {
  description = "Log Analytics Workspace customer ID (GUID). Required for agent configuration and data ingestion API calls."
  # The AVM resource output is marked sensitive (it includes connection keys);
  # workspace_id is not secret but Terraform propagates sensitivity from the parent.
  sensitive = true
  value     = module.log_analytics_workspace.resource.workspace_id
}
