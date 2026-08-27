# UFW + Security Group Defense in Depth

This task demonstrates the "Defense-in-Depth" pattern by keeping a cloud Security Group open while enforcing a stricter local firewall policy on the VM itself.

## 1. Prepare the VM
Run the setup script on the target EC2 instance:

```bash
./setup.sh
```

This installs nginx, enables UFW, and allows SSH + HTTP traffic from anywhere.

## 2. Apply the conflict rule
Use your public IP address to block your own traffic at the OS layer:

```bash
./apply-conflict.sh <YOUR_PUBLIC_IP>
```

The script inserts a deny rule with the highest priority in UFW.

## 3. Why this matters
- The cloud Security Group can still allow port 80 from `0.0.0.0/0`.
- UFW on the VM blocks your specific source IP at the host level.
- This demonstrates layered protection, even when the cloud perimeter remains permissive.

## 4. Validation
Test from your own machine and confirm the request fails. Test from another device or IP and it should still succeed if the Security Group is still open.

## Security note
This pattern is useful for demonstrating the difference between cloud perimeter controls and host-level enforcement.
