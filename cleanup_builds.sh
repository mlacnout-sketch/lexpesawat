#!/bin/bash

# Script untuk menghapus history build yang gagal atau dibatalkan
# Pastikan sudah login ke gh CLI

echo "🔍 Mencari build yang gagal atau dibatalkan di repo ini..."

# Ambil ID build yang gagal (failure) atau dibatalkan (cancelled)
FAILED_RUNS=$(gh run list --json databaseId,conclusion --jq '.[] | select(.conclusion=="failure" or .conclusion=="cancelled") | .databaseId')

if [ -z "$FAILED_RUNS" ]; then
    echo "✅ Tidak ada build gagal yang perlu dihapus."
else
    echo "🗑️ Menghapus build dengan ID berikut:"
    echo "$FAILED_RUNS"
    
    # Hapus satu per satu
    for run_id in $FAILED_RUNS; do
        gh run delete $run_id && echo "   Successfully deleted run $run_id"
    done
    
    echo "✨ Pembersihan selesai!"
fi
