if [[ $1 =~ ([0-9]+)\.([0-9]+) ]]; then 
    IB_GATEWAY_MAJOR=${BASH_REMATCH[1]}
    IB_GATEWAY_MINOR=${BASH_REMATCH[2]}
fi
