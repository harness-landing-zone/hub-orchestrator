# k3d test fleet

Three single-node k3d clusters on one EC2 box inside the **eks-hub VPC**, so the
org-level agent (`gitopsdemo-org-agent`) can register them as ordinary Argo
destinations and a new addons chart version can be rolled at them progressively
before it reaches anything real.

**Why EC2 and not k3d on a laptop.** Argo CD *dials* its destinations. k3d on a
workstation publishes its API to a Docker port map on that machine, which
nothing in eu-west-2 can route to — the cluster Secrets apply cleanly and every
Application against them sits `Unknown` forever. In this VPC the CNI gives
Argo's pods real `10.0.x.x` addresses, so reachability is one security group
rule. No tunnel, no tailnet, no laptop.

---

## Getting a terminal

The box has **no key pair, no public IP and no inbound SSH**. Access is SSM
only. One-time local install:

```bash
brew install --cask session-manager-plugin
```

Then, from this directory:

```bash
aws ssm start-session --region eu-west-2 --target "$(tofu output -raw instance_id)"
```

`tofu output ssm_session_command` prints the same line with the id baked in.

### Once you are on the box

You land as `ssm-user`. `kubectl` works immediately — `/etc/k3d/kubeconfig.yaml`
is world-readable and `KUBECONFIG` is exported from `/etc/profile.d`:

```bash
kubectl config get-contexts
kubectl --context k3d-k3d-1 get nodes
kubectl --context k3d-k3d-2 get pods -A
```

`k3d` and `docker` need the docker socket, so they need root:

```bash
sudo -i
k3d cluster list
```

> If `kubectl config get-contexts` comes back empty, the profile script did not
> load (some SSM shells are non-login). `export KUBECONFIG=/etc/k3d/kubeconfig.yaml`
> and try again — the clusters are fine.

---

## kubectl from your own machine

SSM can port-forward, so you do not need a shell on the box to drive a cluster.
The k3s certs carry `DNS:localhost` and `IP Address:127.0.0.1`, so a forwarded
port validates TLS properly rather than needing `--insecure-skip-tls-verify`:

```bash
aws ssm start-session --region eu-west-2 \
  --target "$(tofu output -raw instance_id)" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6551"],"localPortNumber":["6551"]}'
```

Leave that running, and in another terminal point kubectl at
`https://127.0.0.1:6551`. Copy the kubeconfig down once with:

```bash
aws ssm send-command --region eu-west-2 \
  --instance-ids "$(tofu output -raw instance_id)" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cat /etc/k3d/kubeconfig.yaml"]'
```

...then rewrite the server host to `127.0.0.1` for whichever cluster you
forwarded. One session forwards one port, so run one per cluster.

---

## Starting and stopping

The instance is **stopped on a schedule** (default 20:00 Europe/London) so a
forgotten run cannot bill overnight. It is a *stop*, never a terminate: the
`k3d-fleet` systemd unit runs `k3d cluster start --all` on boot, so all three
clusters come back with their state intact.

```bash
tofu output -raw start_command   # prints the aws ec2 start-instances line
tofu output -raw stop_command
```

Turn the schedule off with `auto_stop_enabled = false` in
`test-fleet.auto.tfvars` if you want the fleet online for a demo.

A stop/start **keeps** the private IP — VPC instances retain their private IPv4
for their whole life — so registrations survive it. What does move the address
is a **replacement**, which any edit to the bootstrap script triggers (see
below). After a replace, re-read `tofu output cluster_endpoints` and update
every registered cluster Secret, or Argo keeps dialling an address that no
longer exists.

---

## What is deliberately fixed

- **API ports 6551/6552/6553.** k3d's default is a random Docker port that
  changes on every recreate — a cluster registered by address would break
  silently every rebuild.
- **`--tls-san=<private ip>`.** k3s only puts localhost/127.0.0.1/0.0.0.0 and
  the container IP in its serving cert, so Argo dialling the private IP would
  otherwise fail hostname verification, and the usual "fix" for that is to
  disable TLS verification permanently.
- **Ingress from the EKS *node* SG**, not the cluster SG. Verified, not assumed:
  the running nodes carry only `hub-cluster-node-*`. With the VPC CNI a pod's
  ENI inherits the node's groups, so allowing the cluster SG would produce a
  rule that looks right and passes no traffic.
- **`fs.inotify.max_user_instances`.** The AL2023 default is low enough that the
  third k3s server comes up with controllers crash-looping on "too many open
  files" — which reads like a broken addon, not a host limit.

## Rebuilding

`user_data_replace_on_change = true`: any edit to the bootstrap script
**replaces the instance**, because the script is the entire definition of what
these clusters are and an in-place update would apply to nothing.

```bash
tofu apply
```

Destroying is safe and reaches nothing outside this workspace — it owns no
network, only an instance, a security group, two IAM roles and a schedule.
