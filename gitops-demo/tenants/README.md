# gitops-demo/tenants/ — tenant desired state for the gitops-demo hub

One directory per tenant. A tenant is a Harness **organization** in phase 1:

```text
gitops-demo/tenants/<org>/values.yaml                       the tenant (walls + namespaced Argo + ORG-scoped Harness agent)
gitops-demo/tenants/<org>/services/<org>_argo_instance.yaml the Harness GitOps Service that represents this instance (Git Experience, remote)
```

Both files are written by the fixed Harness pipeline
`harness_controllers/hub_orchistrator/idp_request_argo_instance`, which the
account IDP Workflow `request_argo_instance` triggers. Do not hand-edit a
pipeline-generated `values.yaml`: the pipeline fails closed on files it did not
write, so a hand edit turns the next request for that org into a platform review.

`gitops-demo/bootstrap/tenants-bootstrap.yaml` reads only `*/values.yaml`; the
`services/` folder is invisible to Argo and exists so the platform team's
inventory Service lives next to the tenant it describes.
