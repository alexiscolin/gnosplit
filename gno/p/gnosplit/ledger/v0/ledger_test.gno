package ledger

import "testing"

func TestParseCents(t *testing.T) {
	cases := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"42", 4200, true},
		{"42.5", 4250, true},
		{"42,50", 4250, true},
		{" 0.01 ", 1, true},
		{"0", 0, false},
		{"12.", 0, false},
		{".5", 0, false},
		{"1.234", 0, false},
		{"1,234.56", 0, false},
		{"-3", 0, false},
		{"1e3", 0, false},
		{"100000000", 10_000_000_000, true},
		{"100000000.01", 0, false},
		{"99999999999999999999", 0, false},
	}
	for _, c := range cases {
		got, ok := ParseCents(c.in)
		if got != c.want || ok != c.ok {
			t.Errorf("ParseCents(%q) = %d, %v; want %d, %v", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestParseAmount(t *testing.T) {
	cents, note, ok := ParseAmount("50 usd x0.92")
	if !ok || cents != 4600 || note != "50.00 USD × 0.92" {
		t.Errorf("foreign: %d %q %v", cents, note, ok)
	}
	cents, note, ok = ParseAmount("10000 JPY x0.0061")
	if !ok || cents != 6100 || note != "10,000.00 JPY × 0.0061" {
		t.Errorf("yen: %d %q %v", cents, note, ok)
	}
	if _, ok := ParseRate("999999999999999999"); ok {
		t.Error("a rate that overflows once scaled is refused")
	}
	if _, _, ok := ParseAmount("50 US$ x1"); ok {
		t.Error("a code is letters only")
	}
	if _, _, ok := ParseAmount("50 USD 0.9"); ok {
		t.Error("a rate starts with x")
	}
	if _, _, ok := ParseAmount("0.01 USD x0.1"); ok {
		t.Error("an amount that converts to 0 is refused")
	}
}

func TestFormat(t *testing.T) {
	cases := map[int64]string{0: "0.00", 5: "0.05", 4250: "42.50", 123456789: "1,234,567.89", -100000: "-1,000.00"}
	for in, want := range cases {
		if got := Format(in); got != want {
			t.Errorf("Format(%d) = %q, want %q", in, got, want)
		}
	}
	if Signed(150) != "+1.50" || Signed(-150) != "-1.50" || Signed(0) != "0.00" {
		t.Error("Signed")
	}
}

func TestSplit(t *testing.T) {
	eq(t, Equal(1000, 3), []int64{334, 333, 333})
	eq(t, Equal(-1000, 3), []int64{-334, -333, -333})
	eq(t, Weighted(1000, []int64{2, 1}), []int64{667, 333})
	eq(t, Weighted(101, []int64{1, 1, 1, 1}), []int64{26, 25, 25, 25})
	eq(t, Weighted(7, []int64{1, 3, 3}), []int64{1, 3, 3})
	eq(t, Weighted(10, []int64{1, 2, 2}), []int64{2, 4, 4})
	for total := int64(1); total < 200; total += 7 {
		var sum int64
		for _, p := range Weighted(total, []int64{3, 5, 7, 1}) {
			sum += p
		}
		if sum != total {
			t.Fatalf("Weighted(%d) sums to %d", total, sum)
		}
	}
}

func TestSettle(t *testing.T) {
	got := Settle([]int64{8450, -3200, -5250})
	want := []Transfer{{2, 0, 5250}, {1, 0, 3200}}
	if len(got) != len(want) {
		t.Fatalf("got %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
	if len(Settle([]int64{0, 0})) != 0 {
		t.Error("nothing to settle")
	}
	bal := []int64{500, -200, 300, -900, 300}
	n := 0
	for _, tr := range Settle(bal) {
		bal[tr.From] += tr.Amount
		bal[tr.To] -= tr.Amount
		n++
	}
	for _, b := range bal {
		if b != 0 {
			t.Fatalf("left %v", bal)
		}
	}
	if n > 4 {
		t.Errorf("%d transfers for 5 members", n)
	}
}

func eq(t *testing.T, got, want []int64) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
}
