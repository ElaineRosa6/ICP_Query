import sys

import pytest

from utils import _run_cmd_capture, is_public_ipv6


@pytest.mark.parametrize(
    "address",
    ["", "not-an-ip", "127.0.0.1", "::1", "fe80::1", "fc00::1", "2001:db8::1"],
)
def test_is_public_ipv6_rejects_invalid_or_non_global_addresses(address):
    assert is_public_ipv6(address) is False


def test_is_public_ipv6_accepts_global_address():
    assert is_public_ipv6("2606:4700:4700::1111") is True


def test_run_cmd_capture_returns_decoded_stdout():
    output = _run_cmd_capture([sys.executable, "-c", "print('capture-ok')"])
    assert output.strip() == "capture-ok"
