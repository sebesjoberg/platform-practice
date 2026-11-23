# Inputs for the VMs (tf-25). Neither has a default: CI sets them from the repo secret LEARNER_IP
# and the repo variable SSH_PUBLIC_KEY (TF_VAR_learner_ip, TF_VAR_ssh_public_key).

variable "learner_ip" {
  description = "Your public IPv4 address: the only source allowed to SSH to the jump VM. CI sets it from the GitHub secret LEARNER_IP (TF_VAR_learner_ip)."
  type        = string
  sensitive   = true # keeps your address out of plan output, which is public in PR comments

  validation {
    condition     = can(cidrhost("${var.learner_ip}/32", 0)) && can(regex("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$", var.learner_ip))
    error_message = "learner_ip must be one IPv4 address (set the GitHub secret LEARNER_IP)."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key for the VMs' admin user. CI sets it from the GitHub variable SSH_PUBLIC_KEY (TF_VAR_ssh_public_key); the private key stays on your machine."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519 ... or ssh-rsa ...); set the GitHub variable SSH_PUBLIC_KEY."
  }
}
