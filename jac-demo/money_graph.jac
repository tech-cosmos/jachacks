"""A tiny money graph: Account -> Merchants -> Payments, audited by a walker."""

node Account {
    has owner: str;
}

node Merchant {
    has name: str;
    has category: str;
}

node Payment {
    has amount: float;
    has month: str;
}

walker audit {
    has grand_total: float = 0.0;
    has findings: list = [];

    # Runs when the walker is spawned on the root node
    can start with Root entry {
        print("== walker spawned on root, looking for accounts ==");
        visit [-->[?:Account]];
    }

    # Runs each time the walker lands on an Account node
    can scan_account with Account entry {
        print(f"Auditing {here.owner}'s account...");
        visit [-->[?:Merchant]];
    }

    # Runs each time the walker lands on a Merchant node
    can inspect with Merchant entry {
        payments = [-->[?:Payment]];
        total = 0.0;
        for p in payments {
            total += p.amount;
        }
        self.grand_total += total;
        print(f"  {here.name} ({here.category}): {len(payments)} charges, ${round(total, 2)}");
        if len(payments) >= 3 {
            self.findings.append(
                f"{here.name} looks like a subscription: "
                f"{len(payments)} charges totaling ${round(total, 2)}"
            );
        }
    }

    # Runs once when the walker has no more nodes to visit
    can wrap_up with exit {
        print("\n== audit report ==");
        print(f"Total spend: ${round(self.grand_total, 2)}");
        for f in self.findings {
            print(f"⚠️  {f}");
        }
    }
}

with entry {
    # Build the graph: root -> account -> merchants -> payments
    acct = Account(owner="Shivam");
    root ++> acct;

    netflix = Merchant(name="Netflix", category="streaming");
    gym = Merchant(name="24hr Fitness", category="fitness");
    coffee = Merchant(name="Blue Bottle", category="coffee");
    acct ++> netflix;
    acct ++> gym;
    acct ++> coffee;

    for month in ["May", "June", "July"] {
        netflix ++> Payment(amount=15.49, month=month);
        gym ++> Payment(amount=49.99, month=month);
    }
    coffee ++> Payment(amount=6.50, month="July");

    # Release the hound
    root spawn audit();
}
