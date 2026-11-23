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

# cap-01: the public half of the CI runner's SSH key (gh-runner on the jump host, an-15). CI sets
# it from the repo variable RUNNER_SSH_PUBLIC_KEY (TF_VAR_runner_ssh_public_key). A default, unlike
# ssh_public_key: the runner only exists once the jump host does, so the first apply has no key,
# and pause/nuke destroy without one.
variable "runner_ssh_public_key" {
  description = "OpenSSH public key of the CI runner (gh-runner on the jump host), authorized for the web VMs' admin user. CI sets it from the GitHub variable RUNNER_SSH_PUBLIC_KEY. Empty: no extra key."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.runner_ssh_public_key) == "" || can(regex("^(ssh-ed25519|ssh-rsa) ", trimspace(var.runner_ssh_public_key)))
    error_message = "runner_ssh_public_key must be empty or an OpenSSH public key (ssh-ed25519 ... or ssh-rsa ...); set the GitHub variable RUNNER_SSH_PUBLIC_KEY from /home/gh-runner/.ssh/id_ed25519.pub on the jump host."
  }
}
