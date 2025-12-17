> [!IMPORTANT]
> **Use at your own risk.**
> This code was generated with the help of AI. Always review scripts before running them in a production environment. This software is provided "as is", without warranty of any kind.

# VCF Offline Depot Automation

**Author:** [jereloh](https://github.com/jereloh/)

This repository contains a Bash script to automate the deployment and configuration of an **Offline Depot Web Server** for VMware Cloud Foundation (VCF).

Designed for **Photon OS 5**, this script streamlines the manual procedure detailed in the official Broadcom documentation. It transforms a complex, multi-step manual process into a single interactive wizard, handling network configuration, disk formatting, Apache setup, and SSL certificate generation.

## Reference Documentation

The logic in this script is based on the official procedure:

* [Set Up an Offline Depot Web Server for VMware Cloud Foundation (Broadcom TechDocs)](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-0/deployment/deploying-a-new-vmware-cloud-foundation-or-vmware-vsphere-foundation-private-cloud-/preparing-your-environment/downloading-binaries-to-the-vcf-installer-appliance/connect-to-an-offline-depot-to-download-binaries/set-up-an-offline-depot-web-server-for-vmware-cloud-foundation.html)

## Features

* **Interactive Setup:** Prompts for Network (IP, Gateway, DNS), Storage (Disk selection), and SSL details.
* **Automatic Formatting:** Handles the partitioning and formatting of the 1TB+ data disk.
* **SSL Flexibility:**
* **Option 1:** Instantly generate and install a Self-Signed Certificate (ideal for Labs/PoC).
* **Option 2:** Generate a CSR and pause for manual signing via an External CA or vCenter VMCA (ideal for Production).


* **Bug Fixes:** Automatically corrects known errata in the manual documentation, including `iptables` syntax errors and Apache `DocumentRoot` misconfigurations specific to Photon OS.
* **Firewall & Security:** Automatically configures `iptables` to allow HTTPS (443) and SSH (22).

## Prerequisites

1. **Photon OS 5:**
Download the latest Photon OS OVA image (Version 5.0 or later) from the official wiki:
* [Download Photon OS](https://github.com/vmware/photon/wiki/Downloading-Photon-OS)


2. **Virtual Machine:** Deploy the OVA.
3. **Storage:** Attach a secondary hard disk (Recommended: 1 TB+) to the VM *before* powering it on.
4. **Access:** You must have root access to the VM.
5. **Public DNS (Optional):** If planning to use Let's Encrypt (see below), you need access to manage public DNS TXT records for domain verification.

## Usage Instructions

### 1. Deploy and Power On

Deploy the Photon OS VM with the secondary disk attached and power it on. Log in as `root`.

### 2. Run the Script

You can run the script using one of the following methods:

**Method A: Direct Execution (curl-to-bash)**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jereloh/vcf-offline-depot-automation/main/setup_vcf_depot.sh)

```

**Method B: Manual Download**

```bash
# Download the file
curl -L -o setup_vcf_depot.sh https://raw.githubusercontent.com/jereloh/vcf-offline-depot-automation/main/setup_vcf_depot.sh

# Make it executable
chmod +x setup_vcf_depot.sh

# Run it
./setup_vcf_depot.sh

```

### 3. Follow Prompts

Enter your network details, select the storage device, and choose your SSL method.

---

## Populating the Depot (Post-Setup)

Once the server is configured, you must populate it with binaries. Choose **one** of the following methods:

### Method A: Automatic (Using Depot Tool)

If you have internet access and a download token, the tool handles downloading and folder structure automatically.

1. **Download the Offline Depot Tool:** Available via the Broadcom Portal under `[My Dashboard > Quick Links]`.
2. **Run the Tool:** Provide your download token. The tool will download the required bundles and populate the depot automatically.

### Method B: Manual Download (Air-Gapped/No Token)

If you cannot use the tool, you must manually construct the depot structure.

1. **Download Metadata Bundle:**
* Download the metadata file (e.g., `vcf-9.0.1.0-offline-depot-metadata`) from the portal.
* Unzip this file. It contains the required folder structure and a manifest list.
* Upload the unzipped contents to `/var/www/html` on your depot server.


2. **Download Software Binaries:**
* Manually download the specific `.ova` and `.iso` files required for your VCF version one by one.
* **Crucial:** You must rename and place these files into the specific folder structure created by the metadata unzip in step 1.



> [!TIP]
> **For VCF 9.0 / VMUG / File Placement Guide:**
> The manual folder structure is strict. If you are unsure exactly which file names correspond to which folder, or are deploying VCF 9.0 using VMUG/VCP entitlements, refer to William Lam's guide for the exact mapping:
> * [How to deploy VVF/VCF 9.0 using VMUG Advantage / VCP Certification entitlement](https://williamlam.com/2025/07/how-to-deploy-vvf-vcf-9-0-using-vmug-advantage-vcp-vcf-certification-entitlement.html)
> 
> 

---

## SSL Certificate Guide

### Option A: Using Let's Encrypt (Docker Method)

For a trusted root certificate without internal CA hassle, use the **DNS Challenge** method.

**Requirements:**

* A separate machine with Docker installed.
* Access to your **Public DNS** to add TXT records for verification.

**Steps:**

1. Run the official Certbot container on your local machine/admin station.
* *Note: Edit `-d depot.mycompany.com` to your actual domain. You can use wildcards (e.g., `*.mydomain.com`) if needed.*


```bash
docker run -it --rm --name certbot \
  -v "$(pwd)/certs:/etc/letsencrypt" \
  certbot/certbot \
  certonly --manual --preferred-challenges dns \
  -d depot.mycompany.com

```


2. **Add TXT Record:** The script will pause and show you a TXT record. Add this to your Public DNS.
3. **Internal DNS:** Ensure your Internal DNS has an A Record pointing `depot.mycompany.com` to the **IP address** of your Offline Depot Appliance.
4. **Retrieve Certs:**
```bash
ls -R ./certs/live/

```


5. Upload these certificates to your Offline Depot appliance.

### Option B: Using Self-Signed Certificates

If you chose the Self-Signed option in the script, note that these are not automatically accepted by the SDDC Manager or VCF Installer.

**To accept Self-Signed certs:**

1. Follow **[KB 403203](https://knowledge.broadcom.com/external/article/403203/set-up-an-offline-depot-from-vcf-90-inst.html)** to import the certificate into the VCF Installer/SDDC Manager trust store.
2. Once trusted, connect the depot in the VCF Installer interface.
