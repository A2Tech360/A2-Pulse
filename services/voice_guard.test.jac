"""Rate limiter and caller-IP tests for speak_brief's guards."""

test "sliding window allows the limit then refuses" {
    reset_rate_limits();
    for i in range(5) {
        assert rate_check(["profile:a", "ip:1"], 5, 600.0, 1000.0 + i) == 0.0;
    }
    retry = rate_check(["profile:a", "ip:1"], 5, 600.0, 1010.0);
    assert 589.0 < retry <= 590.0, retry;
    # Refused attempts are not recorded, and the window slides.
    assert rate_check(["profile:a", "ip:1"], 5, 600.0, 1600.5) == 0.0;
}

test "profile and ip limits are independent" {
    reset_rate_limits();
    for i in range(5) {
        rate_check(["profile:a", "ip:1"], 5, 600.0, 2000.0);
    }
    assert rate_check(["profile:b", "ip:1"], 5, 600.0, 2001.0) > 0.0, "same IP, other profile";
    assert rate_check(["profile:a", "ip:2"], 5, 600.0, 2001.0) > 0.0, "same profile, other IP";
    assert rate_check(["profile:b", "ip:2"], 5, 600.0, 2001.0) == 0.0;
}

test "client ip is unknown outside a request" {
    assert client_ip() == "unknown";
}

obj FakeClient {
    has host: str = "127.0.0.1";
}

obj FakeRequest {
    has client: FakeClient = FakeClient(),
        headers: dict = {};
}

test "forwarded-for is trusted only from a loopback peer" {
    assert _pick_ip("127.0.0.1", "203.0.113.7, 10.0.0.1") == "203.0.113.7";
    assert _pick_ip("127.0.0.1", "") == "127.0.0.1";
    assert _pick_ip("198.51.100.4", "1.2.3.4") == "198.51.100.4";
}

test "client ip is read from a request up the stack" {
    def endpoint(request: any) -> str {
        return client_ip();
    }
    assert endpoint(FakeRequest(client=FakeClient(host="198.51.100.4"))) == "198.51.100.4";
    assert endpoint(FakeRequest(headers={"x-forwarded-for": "203.0.113.9"})) == "203.0.113.9";
}
