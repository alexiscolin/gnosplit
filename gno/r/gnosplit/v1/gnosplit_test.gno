package gnosplit

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	eve   = testutils.TestAddress("eve")
)

// balances is every member's balance, in cents, and checks they sum to zero.
func balances(t *testing.T, gid string) []int64 {
	t.Helper()
	var out []int64
	var sum int64
	for _, m := range mustGroup(gid).Members {
		out = append(out, m.Bal)
		sum += m.Bal
	}
	if sum != 0 {
		t.Fatalf("balances %v sum to %d", out, sum)
	}
	return out
}

func wantBalances(t *testing.T, gid string, want ...int64) {
	t.Helper()
	got := balances(t, gid)
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("balances %v, want %v", got, want)
		}
	}
}

func TestFlow(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	gid := itoa(CreateGroup(cross(cur), "Ski trip", "€", "Alice", "Bob, Chloé"))

	AddExpense(cross(cur), gid, "Groceries", "120", "Alice", "", "Groceries")
	wantBalances(t, gid, 8000, -4000, -4000)

	LinkMember(cross(cur), gid, "bob", bob.String())
	testing.SetRealm(testing.NewUserRealm(bob))
	fuel := AddByShares(cross(cur), gid, "Fuel", "45", "Bob", "Alice:1, Bob:2", "transport")
	wantBalances(t, gid, 6500, -2500, -4000)

	AddTransfer(cross(cur), gid, "Chloé", "Alice", "40")
	wantBalances(t, gid, 2500, -2500, 0)

	AddIncome(cross(cur), gid, "Deposit back", "30", "Alice", "Alice, Bob")
	wantBalances(t, gid, 1000, -1000, 0)

	Delete(cross(cur), gid, itoa(fuel))
	wantBalances(t, gid, 2500, -2500, 0)

	AddByAmounts(cross(cur), gid, "Dinner", "Chloé", "Alice:20, Bob:12.50", "food")
	wantBalances(t, gid, 500, -3750, 3250)

	g := mustGroup(gid)
	uassert.Equal(t, int64(12000-3000+3250), g.Spent)
	uassert.Equal(t, int64(12000), g.ByCat[1])
	uassert.Equal(t, int64(3250), g.ByCat[0])
	uassert.Equal(t, int64(3250), g.Members[2].Paid)
}

func TestForeignAmount(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	gid := itoa(CreateGroup(cross(cur), "NYC", "€", "Alice", "Bob"))
	id := AddExpense(cross(cur), gid, "Taxi", "50 USD x0.92", "Alice", "", "")
	wantBalances(t, gid, 2300, -2300)
	e := mustGroup(gid).Entries.Get(key(id)).(*Entry)
	uassert.Equal(t, "50.00 USD × 0.92", e.Note)
	uassert.Equal(t, len(categories)-1, e.Cat)
}

func TestOnlyEditors(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	gid := itoa(CreateGroup(cross(cur), "Flat", "CHF", "Alice", "Bob"))

	testing.SetRealm(testing.NewUserRealm(eve))
	uassert.AbortsWithMessage(t, cur, "gnosplit: only a member with a linked wallet can change this group", func() {
		AddExpense(cross(cur), gid, "Rent", "100", "Alice", "", "")
	})
	uassert.AbortsWithMessage(t, cur, "gnosplit: only a member with a linked wallet can change this group", func() {
		LinkMember(cross(cur), gid, "Bob", eve.String())
	})

	testing.SetRealm(testing.NewUserRealm(alice))
	LinkMember(cross(cur), gid, "Bob", bob.String())
	uassert.AbortsWithMessage(t, cur, "gnosplit: Bob already has a wallet", func() {
		LinkMember(cross(cur), gid, "Bob", eve.String())
	})
	uassert.AbortsWithMessage(t, cur, "gnosplit: this wallet is already in the group", func() {
		AddMember(cross(cur), gid, "Bobby", bob.String())
	})
}

func TestBadInput(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	gid := itoa(CreateGroup(cross(cur), "Trip", "€", "Alice", "Bob"))
	cases := map[string]func(){
		"gnosplit: an amount is like 42.50, or 50 USD x0.92 for a foreign one": func() {
			AddExpense(cross(cur), gid, "X", "-5", "Alice", "", "")
		},
		"gnosplit: no member called Zoe": func() { AddExpense(cross(cur), gid, "X", "5", "Zoe", "", "") },
		"gnosplit: Bob is listed twice":  func() { AddExpense(cross(cur), gid, "X", "5", "Alice", "Bob, bob", "") },
		"gnosplit: no category snacks":   func() { AddExpense(cross(cur), gid, "X", "5", "Alice", "", "Snacks") },
		"gnosplit: a title is 1 to 60 bytes on one line": func() {
			AddExpense(cross(cur), gid, "a\nb", "5", "Alice", "", "")
		},
		"gnosplit: a share is a whole number from 1 to 1000": func() {
			AddByShares(cross(cur), gid, "X", "5", "Alice", "Alice:0", "")
		},
		"gnosplit: a transfer goes to someone else": func() { AddTransfer(cross(cur), gid, "Bob", "bob", "5") },
		"gnosplit: there is already a alice":        func() { AddMember(cross(cur), gid, "alice", "") },
		"gnosplit: a name is 1 to 24 bytes, without , : ; or =": func() {
			AddMember(cross(cur), gid, "A:B", "")
		},
		"gnosplit: Bob has no wallet to remind": func() {
			AddExpense(cross(cur), gid, "X", "5", "Alice", "", "")
			Remind(cross(cur), gid, "Bob")
		},
	}
	for want, f := range cases {
		uassert.AbortsWithMessage(t, cur, want, f)
	}
}

func TestRemind(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	gid := itoa(CreateGroup(cross(cur), "Lunch", "€", "Alice", ""))
	AddMember(cross(cur), gid, "Bob", bob.String())
	uassert.AbortsWithMessage(t, cur, "gnosplit: Bob owes nothing", func() { Remind(cross(cur), gid, "Bob") })
	AddExpense(cross(cur), gid, "Pizza", "20", "Alice", "", "Food")
	Remind(cross(cur), gid, "Bob")
	uassert.AbortsWithMessage(t, cur, "gnosplit: Bob was reminded less than 12 hours ago", func() {
		Remind(cross(cur), gid, "Bob")
	})
}

func TestSuccessor(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	gid := itoa(CreateGroup(cross(cur), "Old", "€", "Alice", "Bob"))
	AddExpense(cross(cur), gid, "Bread", "3", "Alice", "", "")

	uassert.AbortsWithMessage(t, cur, "gnosplit: only the successor can move a group", func() { MoveOut(cross(cur), gid) })
	owner = alice
	uassert.AbortsWithMessage(t, cur, "gnosplit: a successor is a sibling release under gno.land/r/gnosplit/", func() {
		SetSuccessor(cross(cur), "gno.land/r/evil/v2")
	})
	SetSuccessor(cross(cur), "gno.land/r/gnosplit/v2")

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/gnosplit/v2"))
	out := MoveOut(cross(cur), gid)
	uassert.True(t, strings.Contains(out, "Bread"), out)

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "gnosplit: this group moved to gno.land/r/gnosplit/v2", func() {
		AddExpense(cross(cur), gid, "Milk", "1", "Alice", "", "")
	})
	uassert.True(t, strings.Contains(Render(gid), "This group moved"))
	owner, successor = "", ""
}

func TestRender(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	gid := itoa(CreateGroup(cross(cur), "Beach <b>", "€", "Alice", "Bob, Chloé"))
	AddExpense(cross(cur), gid, "Ice | cream", "12", "Alice", "", "Food")
	LinkMember(cross(cur), gid, "Bob", bob.String())

	contains := func(path string, wants ...string) {
		out := Render(path)
		for _, w := range wants {
			if !strings.Contains(out, w) {
				t.Errorf("Render(%q) lacks %q:\n%s", path, w, out)
			}
		}
	}
	contains("", `<gno-form exec="CreateGroup">`, `<gno-input name="name"`)
	contains(gid, "## Balances", "**8.00 €**", "| Bob | Alice | 4.00 € |", "/settle/1/0/400", "Ice \\| cream")
	contains(gid+"/add", `exec="AddExpense"`, `<gno-input name="group" placeholder="Group" value="`+gid+`" readonly="true" />`,
		`<gno-input type="checkbox" name="forWhom" value="Chloé" checked="true" />`, `value="Alice:1, Bob:1, Chloé:1"`)
	contains(gid+"/settle/1/0/400", `exec="AddTransfer"`, `<gno-select name="from" value="Alice" description="From" />`, `<gno-select name="from" value="Bob" selected="true" />`, `value="4.00"`)
	contains(gid+"/settle", `exec="Remind"`)
	contains(gid+"/members", `exec="LinkMember"`, `<gno-select name="name" value="Chloé"`)
	contains(gid+"/stats", "🍽 Food", "100%")
	contains(gid+"/history", "Page 1 of 1")
	contains(gid+"/e/0", `exec="Delete"`, "| Chloé | 4.00 € |")
	contains(gid+"/csv", "member,address,balance,paid,share", `0,expense,`, `,Ice | cream,Food,Alice,12.00,,`)
	contains("u/"+alice.String(), "Beach", "+8.00 €")
	contains("999", "No group 999")
	contains(gid+"/e/99", "# Not found")
	if strings.Contains(Render(gid), "<b>") {
		t.Error("a group name reaches the page unescaped")
	}
}
