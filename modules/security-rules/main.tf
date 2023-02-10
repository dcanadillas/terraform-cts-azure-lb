locals {
  consul_service_ids = transpose({
    for id, s in var.services : id => [s.name]
  })
  consul_services = {
    for name, ids in local.consul_service_ids : name => [for id in ids : var.services[id]]
  }
  service_addresses = [ for s in var.services : s.address ]
  services_unique_ports = { for service,data in local.consul_services : service => distinct(data[*].port)[0] }
  # Map of vm ==> rg
  # priority ={ for i,j in } 
}

resource "azurerm_network_security_rule" "main" {
  for_each = local.services_unique_ports
  name                        = each.key
  priority                    = 200 + index([for i,j in local.services_unique_ports : i],each.key)
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = each.value
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  resource_group_name         = var.resource_group
  network_security_group_name = var.security_group_name
}

