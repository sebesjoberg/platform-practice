# Input for the web VMs (tf-25), no default: CI sets it from the repo variable SSH_PUBLIC_KEY
# (TF_VAR_ssh_public_key).

variable "ssh_public_key" {
  description = "OpenSSH public key for the web VMs' admin user. CI sets it from the GitHub variable SSH_PUBLIC_KEY (TF_VAR_ssh_public_key)."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519 ... or ssh-rsa ...); set the GitHub variable SSH_PUBLIC_KEY."
  }
}
