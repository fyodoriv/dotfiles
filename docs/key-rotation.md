# Key Rotation

Credentials have a shelf life. Rotating keys limits the blast radius of a compromise and keeps your setup aligned with your organization's security policy. This guide covers rotating both the age encryption key (used by chezmoi for enterprise SSH config) and SSH keys (used for Git and remote access).

**Quick check**: run `dotfiles doctor --module security` to see if anything needs attention right now.

---

## When to Rotate

| Trigger | What to rotate |
|---------|---------------|
| Age key (`~/.config/chezmoi/key.txt`) exposed or copied to an insecure location | Age key |
| Team member with access to the key leaves the organization | Age key |
| Annual rotation as security hygiene | Age key + SSH key |
| SSH key compromised or needs upgrading (e.g., RSA to Ed25519) | SSH key |

---

## Age Key Rotation

The age identity key at `~/.config/chezmoi/key.txt` decrypts any `encrypted_*.age` files chezmoi manages. The base repo ships none. The org overlay carries the encrypted enterprise SSH config. Age encryption is opt-in — set `use_encryption: true` in chezmoi config. The recipient (public key) is stored in `~/.config/chezmoi/chezmoi.yaml`.

### Steps

```bash
# 1. Generate a new key
age-keygen -o ~/.config/chezmoi/key-new.txt
# Note the public key from the output (starts with age1...)

# 2. Decrypt all encrypted files with the OLD key
chezmoi decrypt <path/to/encrypted_file>.age > /tmp/plain-file

# 3. Update chezmoi config with the new recipient (public key)
# Edit ~/.config/chezmoi/chezmoi.yaml: replace age_recipient with the new public key

# 4. Replace the old key with the new one
mv ~/.config/chezmoi/key-new.txt ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# 5. Re-encrypt with the new key
chezmoi encrypt /tmp/plain-file > <path/to/encrypted_file>.age

# 6. Clean up plaintext
rm /tmp/plain-file

# 7. Verify decryption works with the new key
chezmoi cat <path/to/encrypted_file>.age

# 8. Apply and commit
chezmoi apply
git add <path/to/encrypted_file>.age
git commit -m "chore: rotate age encryption key"
```

### Verify after rotation

Both of these should succeed without errors:

```bash
dotfiles doctor --module security
chezmoi apply
```

Confirm `~/.ssh/config.enterprise` is correctly deployed:

```bash
cat ~/.ssh/config.enterprise
```

---

## SSH Key Rotation

### Generating a New SSH Key

```bash
ssh-keygen -t ed25519 -C "your.email@example.com"
```

Accept the default location (`~/.ssh/id_ed25519`) or specify a custom path. Use a passphrase — macOS Keychain will remember it.

### Loading into macOS Keychain

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

This persists across reboots. The SSH config already includes `AddKeysToAgent yes` and `UseKeychain yes`.

### Registering with GitHub

Add the **public** key (`~/.ssh/id_ed25519.pub`) to both:

- **GitHub.com**: <https://github.com/settings/keys>
- **GitHub Enterprise**: `https://<your-ghe-host>/settings/keys` (requires VPN)

Remove the old public key from both after confirming the new key works.

### Updating Chezmoi-Managed SSH Config

The SSH config is managed by chezmoi. If you change key filenames:

1. Edit `private_dot_ssh/private_config.tmpl` in the dotfiles source
2. Run `dotfiles apply` to deploy the updated config
3. Run `dotfiles doctor --module ssh` to verify

### Verifying SSH Access

```bash
ssh -T git@github.com
ssh -T git@<your-ghe-host>  # requires VPN
```

Both should return a "successfully authenticated" message.

---

## Doctor Checks

The security module validates SSH key hygiene automatically:

| Check | What it verifies |
|-------|-----------------|
| `security.ssh_permissions` | `~/.ssh/` directory is 700, private keys are 600 |
| `security.no_agent_forwarding` | No global `ForwardAgent yes` in SSH config |
| `ssh.config_managed` | SSH config is managed by chezmoi |

Run:

```bash
dotfiles doctor --module security
```

---

## Troubleshooting

### "Permission denied (publickey)" after rotation

Key not loaded into the agent.

**Fix:**

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

If that doesn't help, verify the public key is registered on the remote (GitHub, GitHub Enterprise).

### Age decryption fails after rotation

Old key was replaced before re-encrypting. If you have a backup of the old key, temporarily restore it, decrypt, then re-encrypt with the new key:

```bash
# Restore old key temporarily
cp ~/.config/chezmoi/key.txt.bak ~/.config/chezmoi/key.txt

# Decrypt with old key, then follow the rotation steps above
chezmoi decrypt <path/to/encrypted_file>.age > /tmp/plain-file
```

If no backup exists, re-create the encrypted file from its plaintext source and re-encrypt from scratch.

### Doctor reports wrong permissions

**Fix:**

```bash
dotfiles doctor --fix --module security
```

This auto-fixes permissions: 600 for private keys, 700 for `~/.ssh/`.

---

## Further Reading

- [Security model](security-model.md) — full encryption model and trust boundaries
- Your organization's overlay onboarding doc — enterprise encryption setup
- [Troubleshooting](troubleshooting.md) — general troubleshooting guide
