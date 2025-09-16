# CA1 – Infrastructure as Code (IaC)

**Goal:** Implement your CA0 manual deployment entirely via code—spinning up VMs, installing services, wiring the pipeline, and tearing everything down—with minimal manual steps.

---

## What You Must Do

1. **Choose Your IaC Tooling**  
   Select one or combine: Ansible, Terraform (plus Ansible), Puppet, Chef, CloudFormation, ARM/Bicep, etc.

2. **Idempotent Provisioning**
    - Define VM instances (count, size, region) in code.
    - Declare network/subnet, security groups/firewall rules.
    - Install packages and services (Kafka, ZooKeeper, MongoDB/CouchDB, processor container, producer containers).
    - Ensure repeated runs do not produce drift.

3. **Parameterization & Flexibility**
    - Expose variables for region, VM sizes, image tags, topic names, credentials.
    - Provide sensible defaults and allow overrides via CLI flags or variable files.

4. **Secure Secret Handling**
    - Integrate a vault or cloud secret manager (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, etc.).
    - Do **not** check plaintext passwords, tokens, or keys into your repository.

5. **Automated Deployment & Teardown**
    - Create simple commands (or scripts) to deploy **and** destroy the entire environment.
    - Verify that “destroy” cleans up all resources your code created.

6. **Pipeline Validation**
    - After deployment, run a smoke test:
        1. Produce a sample event.
        2. Observe Kafka topic ingestion.
        3. Verify the processor container consumes and writes to the database.
    - Capture logs or screenshots of each stage.

7. **Documentation & Deliverables**
    - **Repository**: Include all IaC code and a top-level `README.md`.
    - **README.md** should describe:
        - Prerequisites (CLI versions, credentials setup).
        - How to deploy (one or two commands).
        - How to destroy.
        - How to run validation tests.
        - Any deviations from CA0 or your reference stack.
    - **Run Logs**: Attach logs or console output showing successful create/destroy and pipeline test.
    - **Outputs Summary**: List endpoints/IPs, topic names, database connection strings, and validation results.

---

## How You Will Be Graded

- **Idempotency & Reproducibility** (25%)  
  Deployment can be run multiple times with consistent results; destroy leaves no remnants.
- **Security & Secret Management** (15%)  
  No secrets in code; use a vault or secret manager properly.
- **Pipeline Correctness** (20%)  
  Kafka broker, processor, producers, and DB all deployed and correctly wired with smoke-test proof.
- **Documentation & Ease of Use** (25%)  
  Clear README, parameter descriptions, and simple deploy/destroy instructions.
- **Cloud-Modality Execution** (10%)  
  Proper use of provider-specific features (modules, providers, resource types).
- **Automation Quality** (5%)  
  Code readability, modularity, and appropriate abstraction of variables.

---

## Tips & Best Practices

- Modularize your code (e.g., separate networking, compute, and application modules).
- Use version control branches or tags to capture “before” and “after” states.
- Validate your IaC with linting or dry-run features (`terraform plan`, `ansible --check`, etc.).
- Store secrets in a dedicated workspace or encrypted file—not in plain text.
- Test destroy workflows early to avoid lingering cloud charges.
- Keep your README up-to-date as you iterate on your code.

## Troubleshooting

### Resource Ownership and Manual Cleanup
If you previously created AWS resources (such as Elastic IPs, NAT Gateways, or EC2 instances) using the AWS root user or a different IAM user, your new `ansible-deployer` IAM user may not have permission to delete or release those resources. This can result in errors or orphaned resources when running the teardown playbook.

**Solution:**
- Always use your `ansible-deployer` IAM user for all resource creation and management for this project.
- If you encounter errors about permissions or resources that cannot be deleted, log in to the AWS Console as the root user (or the user that created the resource) and manually delete those resources.
- Common resources that may require manual cleanup include Elastic IPs, NAT Gateways, and EC2 instances created outside of your automation workflow.

This will help ensure your teardown playbook can fully clean up all resources and prevent unexpected AWS charges.