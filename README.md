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

1.  **Photon OS 5:**
    Download the latest Photon OS OVA image (Version 5.0 or later) from the official wiki:
    * [Download Photon OS](https://github.com/vmware/photon/wiki/Downloading-Photon-OS)
2.  **Virtual Machine:** Deploy the OVA.
3.  **Storage:** Attach a secondary hard disk (Recommended: 1 TB+) to the VM *before* powering it on.
4.  **Access:** You must have root access to the VM.

## Usage Instructions

1.  **Deploy and Power On:**
    Deploy the Photon OS VM with the secondary disk attached and power it on. Log in as `root`.

2.  **Running the Script:**
-    Run the following command on the VM to download the script directly:
    ```
    bash <(curl -fsSL https://raw.githubusercontent.com/jereloh/vcf-offline-depot-automation/main/setup_vcf_depot.sh)
    ```

    **or** 

-   **Download the file**
   ```curl -L -o setup_vcf_depot.sh https://raw.githubusercontent.com/jereloh/vcf-offline-depot-automation/main/setup_vcf_depot.sh```
-   **Make it executable**
   ```chmod +x setup_vcf_depot.sh```
   
-   **Run it**
   ```./setup_vcf_depot.sh```

3.  **Follow Prompts:**
    Enter your network details, select the storage device, and choose your SSL method.

## Using Self Signed
Self-signed certs are not automatically accepted by SDDC Manager/VCF installer, you will be required to import these certs into SDDC Mangaer/VCF Installer following this [KB 403203](https://knowledge.broadcom.com/external/article/403203/set-up-an-offline-depot-from-vcf-90-inst.html)

## Using Let's Encrypt SSL (Docker Method)
If you require a trusted root certificate (e.g., Let's Encrypt) instead of a self-signed one, you can generate the certificates on a separate machine using Docker.

Requirements:

A separate machine with Docker installed.

Public DNS access to add TXT records for domain verification.

Run the official Certbot container:
edit -d depot.mycompany.com to -d mydomain.com *.mydomain.com fo root/wildcards if required
```
docker run -it --rm --name certbot \
  -v "$(pwd)/certs:/etc/letsencrypt" \
  certbot/certbot \
  certonly --manual --preferred-challenges dns \
  -d depot.mycompany.com
```
Retrieve certs via:
```ls -R ./certs/live/```

Add the TXT records in public dns

For internal DNS create the same DNS record pointing to the ip address of the appliance

