
output "ports" {
  value = local.group_ports 
}
# output "services" {
#   value = local.consul_services
# }
 
output "loadbalancer" {
  value = module.lb.lb_fqdn
}