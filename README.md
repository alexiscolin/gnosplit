# gnosplit

Split expenses with friends, then settle up in as few transfers as possible. Like Tricount, but on [gno.land](https://gno.land): no account, no ads, no company that can close it.

You make a group for a trip, a flatshare or a dinner, list your friends, and add what each one paid. gnosplit keeps everyone's balance and tells you who should pay whom. Your friends don't need a wallet to be in a group; they need one only to add expenses themselves, and to get notified when something concerns them.

## What you can do

- Split an expense equally, by shares (Alice pays twice as much as Bob) or by exact amounts.
- Pay in another currency: write `50 USD x0.92` and it's converted.
- Record money you got back (a refund, a deposit) and payments between friends.
- See balances, the transfers that settle everything, stats by category and by person, the full history, and a CSV export.
- Get a browser notification through [gnotif](https://gnotif.xyz) when someone adds an expense for you, pays you, or reminds you that you owe them.

It all works from gnoweb, the chain's own website: no app to install. A nicer app can come later on top of the same realm.

**One thing to know:** a group lives on a public blockchain, so anyone with its link can read it. Use first names and keep private details out of titles.

## How it's built

```
gno/p/gnosplit/ledger/v0   the maths: amounts, splits, who pays whom (no state)
gno/r/gnosplit/v1          groups, members, expenses, the pages and the notifications
tools/deploy.sh            deploys both to onyx, signed with your own key
```

Balances are updated on every write, so opening a group never adds up its whole history. To settle up, the largest debt pays the largest credit until everyone is at zero: never more than one transfer less than there are members.

A future version will be a new realm, `gnosplit/v2`. Groups move to it one at a time, when one of their members asks; the old one stays readable.

## Try it locally

You need [Go](https://go.dev/dl/). The deploy script builds the matching `gno` once, or you can run the tests with your own:

```sh
gno mod download -remote-overrides "gno.land=https://rpc.onyx.testnets.gno.land:443"
gno test ./gno/...
```

## Deploy

On the machine that holds your gnokey key:

```sh
tools/deploy.sh --dry-run <key name> <your namespace>   # checks everything, signs nothing
tools/deploy.sh <key name> <your namespace>
```

It runs on onyx only for now, because gnotif is there.

## Licence

[CODE LICENCE]
