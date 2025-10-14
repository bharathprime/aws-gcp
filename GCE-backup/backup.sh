#!/bin/bash
set -e

echo "===================================="
echo " Backup Setup Script"
echo " 1) Virtual Machines (VMs)"
echo " 2) Cloud SQL Instances"
echo "===================================="
read -p "Select backup target [1/2]: " CHOICE

if [ "$CHOICE" == "1" ]; then
    ###########################################
    # VM SNAPSHOT BACKUP (your script version)
    ###########################################
    SCHEDULE_NAME="daily-snapshot-schedule"

    echo "Fetching available VMs..."
    VM_LIST=$(gcloud compute instances list --format="value(name,zone)")

    if [ -z "$VM_LIST" ]; then
        echo "❌ No VMs found in the current project."
        exit 1
    fi

    echo "Available VMs:"
    i=1
    declare -A VM_MAP
    while read -r VM_NAME VM_ZONE; do
        echo "$i) $VM_NAME ($VM_ZONE)"
        VM_MAP[$i]="$VM_NAME|$VM_ZONE"
        ((i++))
    done <<< "$VM_LIST"

    read -p "Select VM numbers (comma separated, e.g. 1,3,5): " CHOICES

    IFS=',' read -ra SELECTED_VMS <<< "$CHOICES"
    for CHOICE in "${SELECTED_VMS[@]}"; do
        CHOICE=$(echo $CHOICE | xargs) # trim spaces
        SELECTED="${VM_MAP[$CHOICE]}"

        if [ -z "$SELECTED" ]; then
            echo "❌ Invalid selection: $CHOICE"
            continue
        fi

        VM_NAME=$(echo $SELECTED | cut -d'|' -f1)
        ZONE=$(echo $SELECTED | cut -d'|' -f2)
        REGION=$(echo $ZONE | sed 's/-[a-z]$//')

        echo "-----------------------------------"
        echo "✅ Processing VM: $VM_NAME"
        echo " Zone: $ZONE"
        echo " Region: $REGION"

        if ! gcloud compute resource-policies describe $SCHEDULE_NAME --region=$REGION >/dev/null 2>&1; then
            echo "⚙️ Snapshot schedule $SCHEDULE_NAME does not exist in $REGION."
            read -p "Enter retention period in days (e.g. 7): " RETENTION_DAYS
            read -p "Enter snapshot time (e.g. 2am or 2pm): " SNAPSHOT_TIME

            SNAPSHOT_HOUR=$(date -d "$SNAPSHOT_TIME" +%H 2>/dev/null || true)
            if [ -z "$SNAPSHOT_HOUR" ]; then
                echo "❌ Invalid time format: $SNAPSHOT_TIME"
                exit 1
            fi

            echo "Creating snapshot schedule: $SCHEDULE_NAME in $REGION"
            gcloud compute resource-policies create snapshot-schedule $SCHEDULE_NAME \
                --region=$REGION \
                --max-retention-days=$RETENTION_DAYS \
                --on-source-disk-delete=apply-retention-policy \
                --daily-schedule \
                --start-time=${SNAPSHOT_HOUR}:00
        else
            echo "ℹ️ Snapshot schedule $SCHEDULE_NAME already exists in region $REGION"
        fi

        DISKS=$(gcloud compute instances describe "$VM_NAME" \
            --zone="$ZONE" \
            --format="value(disks[].source)")

        for DISK_URI in $DISKS; do
            DISK_NAME=$(basename $DISK_URI)
            echo "Attaching disk $DISK_NAME to snapshot schedule $SCHEDULE_NAME"
            gcloud compute disks add-resource-policies "$DISK_NAME" \
                --zone="$ZONE" \
                --resource-policies="$SCHEDULE_NAME"
        done
    done

    echo "✅ Snapshot scheduling setup completed for all selected VMs."

elif [ "$CHOICE" == "2" ]; then
    ###########################################
    # CLOUD SQL AUTOMATED BACKUP
    ###########################################
    echo "Fetching available Cloud SQL instances..."
    INSTANCE_LIST=$(gcloud sql instances list --format="value(name)")

    if [ -z "$INSTANCE_LIST" ]; then
        echo "❌ No Cloud SQL instances found in the current project."
        exit 1
    fi

    echo "Available Cloud SQL instances:"
    i=1
    declare -A INST_MAP
    while read -r INST; do
        echo "$i) $INST"
        INST_MAP[$i]="$INST"
        ((i++))
    done <<< "$INSTANCE_LIST"

    read -p "Select instance numbers (comma separated, e.g. 1,2,3): " CHOICES
    read -p "Enter retention days (default 7): " RETENTION_DAYS
    RETENTION_DAYS=${RETENTION_DAYS:-7}

    IFS=',' read -ra SELECTED_INST <<< "$CHOICES"
    for CHOICE in "${SELECTED_INST[@]}"; do
        CHOICE=$(echo $CHOICE | xargs)
        INST_NAME="${INST_MAP[$CHOICE]}"

        if [ -z "$INST_NAME" ]; then
            echo "❌ Invalid selection: $CHOICE"
            continue
        fi

        echo "-----------------------------------"
        echo "✅ Enabling automated backup for Cloud SQL instance: $INST_NAME"
	
	gcloud sql instances patch "$INST_NAME" --retained-backups-count="$RETENTION_DAYS"

    done

    echo "✅ Cloud SQL automated backups configured."

else
    echo "❌ Invalid choice. Please enter 1 or 2."
    exit 1
fi

