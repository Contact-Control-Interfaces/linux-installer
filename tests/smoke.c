// Opens a Session against the installed Contact CI Service through the Core
// C API, the way an application does, and touches the shared haptic state.
// No glove is needed. Exits non-zero, saying why, if anything fails.
//
//     gcc tests/smoke.c -o smoke -lccic
//     ./smoke [service-version-prefix]
//
// With an argument, the Service must report a version that starts with it.

#include <contactci.h>

#include <stdio.h>
#include <string.h>

static int fail(const char *what, CciStatus status) {
    fprintf(stderr, "smoke: %s failed: %s\n", what, cci_get_error_string(status));
    return 1;
}

int main(int argc, char **argv) {
    const char *expected = argc > 1 ? argv[1] : "";

    CciSessionHandle session = NULL;
    CciStatus status = cci_create_mutable_haptic_session(&session);
    if (status != CCI_SUCCESS) return fail("cci_create_mutable_haptic_session", status);

    status = cci_is_session_connected(session);
    if (status != CCI_SUCCESS) return fail("cci_is_session_connected", status);

    const char *version = cci_get_session_service_version(session);
    printf("Service version: %s\n", version ? version : "(none)");
    if (!version || strncmp(version, expected, strlen(expected)) != 0) {
        fprintf(stderr, "smoke: expected a Service version starting with \"%s\"\n", expected);
        return 1;
    }

    // The Session's own haptic state: shared memory the Service created for it.
    HapticState *left = NULL, *right = NULL;
    status = cci_get_session_haptic_state(session, &left, &right);
    if (status != CCI_SUCCESS) return fail("cci_get_session_haptic_state", status);
    if (!left || !right) {
        fprintf(stderr, "smoke: the Session has no haptic state\n");
        return 1;
    }

    status = cci_signal_session_haptic_state_changed(session);
    if (status != CCI_SUCCESS) return fail("cci_signal_session_haptic_state_changed", status);

    // The global haptic state: what the Service sends to the gloves.
    const HapticState *global_left = NULL, *global_right = NULL;
    status = cci_get_global_haptic_state(session, &global_left, &global_right);
    if (status != CCI_SUCCESS) return fail("cci_get_global_haptic_state", status);
    if (!global_left || !global_right) {
        fprintf(stderr, "smoke: the Service has no global haptic state\n");
        return 1;
    }

    cci_close_session(session);
    puts("smoke: ok");
    return 0;
}
