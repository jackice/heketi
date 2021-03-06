#!/bin/bash

fail() {
    echo "==> ERROR: $*"
    exit 1
}

println() {
    echo "==> $1"
}

_sudo() {
    if [[ ${UID} = 0 || "$HEKETI_TEST_USE_SUDO" = "no" ]]; then
        "${@}"
    else
        sudo -E "${@}"
    fi
}

HEKETI_PID=
start_heketi() {
    HEKETI_PID=
    ( cd "$HEKETI_SERVER_BUILD_DIR" && make && cp heketi "$HEKETI_SERVER" )
    if [ $? -ne 0 ] ; then
        fail "Unable to build Heketi"
    fi

    # Start server
    rm -f heketi.db > /dev/null 2>&1
    $HEKETI_SERVER --config=config/heketi.json &
    HEKETI_PID=$!
    sleep 2
}

stop_heketi() {
    if [[ -z "$HEKETI_PID" ]]; then
        # heketi pid was not set, nothing to stop
        return 0
    fi

    kill "$HEKETI_PID"
    sleep 0.2
    for i in $(seq 1 5); do
        if [[ ! -d "/proc/${HEKETI_PID}" ]]; then
            break
        fi
        echo "WARNING: Heketi server may still be running."
        ps -f "$HEKETI_PID"
        kill "$HEKETI_PID"
        sleep 1
    done
}

start_vagrant() {
    cd vagrant || fail "Unable to 'cd vagrant'."
    _sudo ./up.sh || fail "unable to start vagrant virtual machines"
    cd ..
}

teardown_vagrant() {
    cd vagrant || fail "Unable to 'cd vagrant'."
    _sudo vagrant destroy -f
    cd ..
}

run_go_tests() {
    cd tests || fail "Unable to 'cd tests'."
    go test -timeout=1h -tags functional -v
    gotest_result=$?
    cd ..
}

force_cleanup_libvirt_disks() {
    # Sometimes disks are not deleted
    for i in $(_sudo virsh vol-list default | grep '\.disk' | awk '{print $1}') ; do
        _sudo virsh vol-delete --pool default "${i}" || fail "Unable to delete disk $i"
    done
}

teardown() {
    if [[ "$HEKETI_TEST_VAGRANT" != "no" ]]
    then
        teardown_vagrant
        force_cleanup_libvirt_disks
    fi
    rm -f heketi.db > /dev/null 2>&1
}

setup_test_paths() {
    cd "$SCRIPT_DIR" || return 0
    if [[ -z "${FUNCTIONAL_DIR}" ]]; then
        echo "error: env var FUNCTIONAL_DIR not set" >&2
        exit 2
    fi
    : "${HEKETI_SERVER_BUILD_DIR:=$FUNCTIONAL_DIR/../..}"
    : "${HEKETI_SERVER:=${FUNCTIONAL_DIR}/heketi-server}"
}

pause_test() {
    if [[ "$1" = "yes" ]]; then
        read -r -p "Press ENTER to continue. "
    fi
}

functional_tests() {
    setup_test_paths
    if [[ "$HEKETI_TEST_VAGRANT" != "no" ]]
    then
        start_vagrant
    fi
    start_heketi

    pause_test "$HEKETI_TEST_PAUSE_BEFORE"
    run_go_tests
    pause_test "$HEKETI_TEST_PAUSE_AFTER"

    stop_heketi
    if [[ "$HEKETI_TEST_CLEANUP" != "no" ]]
    then
        teardown
    fi

    exit $gotest_result
}

