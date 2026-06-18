# Terraform for AWS & Databricks Data Platform

This repository contains Terraform code to provision an end-to-end data platform on AWS, leveraging Databricks for advanced analytics and data processing. The infrastructure is designed to handle both real-time data ingestion and scheduled batch processing.

## The two repositories

This repo is the **infrastructure layer** of **lmx**; its sibling, [lmx-data](https://github.com/your-account/lmx-data), is the **data layer**.

The boundary is deliberate: **this repo owns *where things live*; `lmx-data` owns *what runs in them*.** Terraform here provisions the foundation — AWS resources, Databricks workspaces, Unity Catalog catalogs/schemas and grants, SQL warehouses, and the Lakebase serving layer. The data layer treats those as a given (it never runs `CREATE SCHEMA`) and deploys connectors, medallion transforms, and serving pipelines with **Databricks Asset Bundles (DABs)** — exposing the gold layer to a frontend app, Databricks Apps, Genie, Lakebase synced tables, and AI/ML workloads.

Why two repos:

- **Independent lifecycles** — foundation changes are rare and deliberate; data pipelines change constantly.
- **Smaller blast radius** — `terraform plan/apply` against catalogs, workspaces, and IAM stays isolated from day-to-day pipeline edits.
- **Least-privilege ownership** — Terraform state and cloud-admin live here; data engineers never need them.
- **One toolchain per repo** — Terraform here, DABs there — clean, separate CI for each.

## High-Level Architecture

The project deploys the following key components:

### 1. AWS Foundational Infrastructure

-   **VPC**: A custom Virtual Private Cloud (`lmx-vpc-dev`) is created with public and private subnets to ensure a secure and isolated network environment. Subnets are specifically allocated for Databricks and AWS Glue.
-   **S3 Buckets**:
    -   `lmx-s3-dev` & `lmx-s3-prod`: For storing development and production data.
    -   `lmx-glue-operational`: For housing Glue ETL scripts and temporary files.
    -   `lmx-databricks-root`: The root storage for the Databricks workspace and Unity Catalog metastore.
-   **VPC Endpoints**: An S3 Gateway Endpoint is established to allow resources in the private subnets (like Glue jobs and Databricks clusters) to access S3 securely and efficiently without traversing the public internet.

---

### 2. Batch Processing

-   **AWS Glue**: A scheduled AWS Glue job (`acme_job`) is defined to run daily. This is intended for batch ETL processes that transform data within the S3 data lake.

---

### 3. Real-Time Data Ingestion Pipeline

-   **API Gateway**: An HTTP API is set up with a custom domain (`api.lmx.com`). It's configured to receive `POST` requests (webhooks) and requires an API key for authorization.
-   **Kinesis Data Stream**: The API Gateway is directly integrated with a Kinesis stream (`lmx-kinesis-dev`). Incoming data payloads are transformed and sent to the stream, enabling real-time data capture.

---

### 4. Data Processing & Analytics with Databricks

The configuration is split into two modules for clarity and reusability:

-   **`databricks_account` Module**: This module handles the initial setup at the Databricks account level.
    -   Creates the necessary IAM roles for cross-account access between AWS and Databricks.
    -   Provisions the Databricks workspace (`lmx-develop`).
    -   Sets up the Unity Catalog (UC) Metastore for centralized data governance.
    -   Configures Databricks users and groups.

-   **`databricks_workspace_develop` Module**: This module configures the resources *inside* the Databricks workspace.
    -   **Unity Catalog**: Creates Storage Credentials and External Locations to securely connect the Unity Catalog to the S3 data lake (`lmx-s3-dev`).
    -   **3-Level Namespace**: Establishes a `acme_dev` catalog with `bronze`, `silver`, and `gold` schemas to organize data according to a medallion architecture.
    -   **Compute**: Provisions shared and user-specific clusters, as well as a Databricks SQL Warehouse for BI and SQL workloads.
    -   **Permissions**: Manages grants within Unity Catalog, assigning appropriate access levels to users and groups.

---

## How to Use

### Prerequisites

1.  **Terraform CLI**: Ensure you have Terraform installed.
2.  **AWS Credentials**: Configure your AWS access keys with permissions to create the resources defined in the files.
3.  **Databricks Credentials**: Provide your Databricks Account ID and a Client ID/Secret for an account-level service principal.

### Deployment

1.  Initialize the Terraform project:
    ```bash
    terraform init
    ```

2.  Create a `terraform.tfvars` file to provide values for the required variables (e.g., `aws_account_id`, `databricks_account_id`, etc.).

3.  Preview the changes:
    ```bash
    terraform plan
    ```

4.  Apply the configuration:
    ```bash
    terraform apply
    ```