output "public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "ssh" {
  value = "ssh ztb@${azurerm_public_ip.main.ip_address}"
}

# k3s writes its kubeconfig for 127.0.0.1, so point it at the public IP instead.
output "get_kubeconfig" {
  value = "ssh ztb@${azurerm_public_ip.main.ip_address} sudo cat /etc/rancher/k3s/k3s.yaml | sed 's/127.0.0.1/${azurerm_public_ip.main.ip_address}/' > ~/.kube/ztb-k3s.yaml"
}
