variable "budget_name" {
  description = "The name of the budget"
  type        = string
}

variable "budget_limit" {
  description = "The limit of the budget"
  type        = number
}

variable "budget_email" {
  description = "The email address to send budget notifications to"
  type        = string
}

variable "budget_time_unit" {
  description = "The time unit for the budget (e.g., MONTHLY, QUARTERLY, ANNUALLY)"
  type        = string
  default     = "MONTHLY"
}

variable "budget_cost_types" {
  description = "The cost types for the budget"
  type        = map(string)
  default     = {}
}

variable "budget_cost_filters" {
  description = "The cost filters for the budget"
  type        = map(string)
  default     = {}
}

variable "budget_notification_threshold" {
  description = "The threshold for budget notifications"
  type        = number
  default     = 80
}

variable "budget_notification_comparison_operator" {
  description = "The comparison operator for budget notifications"
  type        = string
  default     = "GREATER_THAN"
}

variable "budget_notification_type" {
  description = "The type of budget notification (e.g., ACTUAL, FORECASTED)"
  type        = string
  default     = "ACTUAL"
}
