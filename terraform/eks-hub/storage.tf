################################################################################
# Default StorageClass
#
# WHY THIS FILE EXISTS: this cluster had NO usable storage at all. Three
# separate problems, and each one alone is enough to leave a PVC Pending
# forever with no event that names the real cause:
#
#   1. No default StorageClass. The only class present (gp2) carries no
#      storageclass.kubernetes.io/is-default-class annotation, so any PVC that
#      omits storageClassName binds to nothing.
#   2. gp2 uses the IN-TREE provisioner kubernetes.io/aws-ebs, which was
#      REMOVED in Kubernetes 1.31. This cluster is 1.36, so that class cannot
#      provision regardless of anything else.
#   3. The aws-ebs-csi-driver addon had no IAM identity - see the
#      aws_ebs_csi_pod_identity module in pod-identity.tf, which was commented
#      out. Fixed there; this file is useless without it.
#
# The gp2 class is left in place deliberately rather than deleted: it is
# created by EKS itself, nothing uses it (there were zero PVCs on the cluster),
# and removing an EKS-managed object invites it to come back on the next addon
# reconcile. It is simply never selected now that a real default exists.
################################################################################

resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"

    annotations = {
      # Makes this the class a PVC gets when it names none. Exactly ONE class
      # may carry this - a second default makes the choice non-deterministic
      # and Kubernetes will not pick for you.
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  # The CSI driver, NOT kubernetes.io/aws-ebs. This is the whole point of the
  # file: the in-tree provisioner no longer exists in this Kubernetes version.
  storage_provisioner = "ebs.csi.aws.com"

  # Delete, matching gp2 and the EKS default. The guard against losing a TSDB
  # is NOT the reclaim policy - it is prune: false on the monitoring
  # ApplicationSet, so removing a values entry cannot delete the PVC that holds
  # the history. Retain would avoid that risk but leaves orphaned EBS volumes
  # billing quietly after every cluster teardown.
  reclaim_policy = "Delete"

  # Bind only once a pod is scheduled, so the volume is created in the SAME
  # availability zone as its consumer. EBS volumes are zonal: bind immediately
  # and a multi-AZ cluster will eventually place a pod in one zone and its
  # volume in another, which is unrecoverable without deleting the PVC. This
  # cluster spans two AZs, so it is not hypothetical.
  volume_binding_mode = "WaitForFirstConsumer"

  # gp2 cannot expand (allowVolumeExpansion: false), which makes running out of
  # space terminal. gp3 can. This does NOT make a StatefulSet's
  # volumeClaimTemplate editable - that field stays immutable and growing a
  # volume still means editing the PVC directly and restarting the workload -
  # but it means the operation is possible at all.
  allow_volume_expansion = true

  parameters = {
    # gp3 over gp2 deliberately: cheaper per GB, and it decouples IOPS from
    # volume size. gp2 derives IOPS from capacity (3 IOPS/GB), so a small TSDB
    # volume gets a small IOPS budget and compaction suffers. gp3 gives a flat
    # 3000 IOPS / 125 MB/s baseline at any size.
    type   = "gp3"
    fsType = "ext4"

    # Encryption at rest with the AWS-managed key. This is why
    # aws_ebs_csi_kms_arns is set on the pod identity module - without those
    # KMS permissions the driver can create an unencrypted volume but not an
    # encrypted one, and the failure surfaces as a generic provisioning error.
    encrypted = "true"
  }

  # Ordering, not decoration: without the IAM identity the driver cannot serve
  # a CreateVolume call, so creating the class first would produce a default
  # StorageClass that silently fails every claim.
  depends_on = [module.aws_ebs_csi_pod_identity]
}
