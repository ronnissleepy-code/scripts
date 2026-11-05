#!/bin/sh
# throwaway: measure github code-search queries - how many unique PAIRED ip hits?
# (a highlight of "root@1.2.3.4" is a proven pair; an ip scraped from a README
#  anywhere in the repo is not - that is why the queue is half placeholders)
TOK=$(grep -m1 '^GITHUB_TOKEN=' worker.env | cut -d'"' -f2)
q() {
    n=$1
    body=$(curl -sS -m 20 -H "Authorization: token $TOK" \
        -H "Accept: application/vnd.github.text-match+json" \
        -H "User-Agent: probe" \
        "https://api.github.com/search/code?per_page=100&q=$(printf '%s' "$1" | sed 's/ /%20/g')")
    total=$(printf '%s' "$body" | grep -o '"total_count":[0-9]*' | head -1 | cut -d: -f2)
    all=$(printf '%s' "$body" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | wc -l)
    uni=$(printf '%s' "$body" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort -u | wc -l)
    pairs=$(printf '%s' "$body" | grep -o '[A-Za-z_-]\{2,\}@[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort -u | wc -l)
    echo "== $n : total=$total ip_occurrences=$all unique_ips=$uni user_at_ip=$pairs"
    printf '%s' "$body" | grep -o '[A-Za-z_-]\{2,\}@[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort -u | head -6 | paste -sd,
    echo
}
q "root@  <-- paired by construction" "root@"
q "ubuntu@"                          "ubuntu@"
q "ec2-user@"                        "ec2-user@"
q "admin@"                           "admin@"
q "HostName (ssh config)"            "HostName"
q "filename:id_rsa (current)"        "filename:id_rsa"
q "path:.ssh filename:config"        "path:.ssh%20filename:config"
q "filename:terraform.tfstate"       "filename:terraform.tfstate"
q "ansible_host"                     "ansible_host"
