
# VPC
output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "The primary IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

# Subnets
output "public_subnet_ids" {
  description = "Map of availability zone → subnet ID for all public subnets."
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "public_subnet_ids_list" {
  description = "Ordered list of public subnet IDs (sorted by AZ name). Useful when a list is required by downstream resources."
  value       = [for az in sort(keys(aws_subnet.public)) : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Map of availability zone → subnet ID for all private subnets."
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "private_subnet_ids_list" {
  description = "Ordered list of private subnet IDs (sorted by AZ name). Useful when a list is required by downstream resources."
  value       = [for az in sort(keys(aws_subnet.private)) : aws_subnet.private[az].id]
}

# Internet Gateway
output "internet_gateway_id" {
  description = "The ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

# NAT Gateway
output "nat_gateway_id" {
  description = "The ID of the NAT Gateway. Empty string when enable_nat_gateway is false."
  value       = try(aws_nat_gateway.this[0].id, "")
}

output "nat_gateway_public_ip" {
  description = "The public Elastic IP address associated with the NAT Gateway. Empty string when enable_nat_gateway is false."
  value       = try(aws_eip.nat[0].public_ip, "")
}

# Route Tables
output "public_route_table_id" {
  description = "The ID of the public route table (routes traffic to the Internet Gateway)."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "The ID of the private route table (routes traffic to the NAT Gateway when enabled)."
  value       = aws_route_table.private.id
}
