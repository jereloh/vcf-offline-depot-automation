### Important Disclaimer

**Use at your own risk. This code was generated with the help of AI.**
Always review scripts before running them in a production environment. This software is provided "as is", without warranty of any kind.

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

2.  **Download the Script:**
    Run the following command on the VM to download the script directly:
    ```bash
    wget https://raw.githubusercontent.com/jereloh/vcf-offline-depot-automation/main/setup_vcf_depot.sh
    ```

3.  **Make Executable:**
    Grant execution permissions to the script:
    ```bash
    chmod +x setup_vcf_depot.sh
    ```

4.  **Run the Wizard:**
    Execute the script:
    ```bash
    ./setup_vcf_depot.sh
    ```

5.  **Follow Prompts:**
    Enter your network details, select the storage device, and choose your SSL method.

6.  **Finalize:**
    The system will perform a system update and automatically reboot after a 5-second countdown. Once the system comes back up, your Offline Depot is ready for use.
