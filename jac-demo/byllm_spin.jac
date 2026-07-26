"""byLLM demo: functions implemented by an LLM — no prompts written anywhere."""

import from byllm.llm { Model }

glob llm = Model(model_name="gemini/gemini-2.5-flash");

obj Txn {
    has merchant: str;
    has amount: float;
    has category: str;
    has looks_recurring: bool;
}

"""Parse raw bank statement lines into clean, structured transactions."""
def parse_statement(raw: str) -> list[Txn] by llm();

"""Write a witty but genuinely useful 2-sentence verdict on this spending."""
def spending_verdict(txns: list[Txn], monthly_income: float) -> str by llm();

with entry {
    raw = """
    07/01 NETFLIX.COM             15.49
    07/03 SQ *BLUE BOTTLE COFFEE   6.50
    07/05 24 HOUR FITNESS USA     49.99
    07/12 UBER *EATS              34.20
    07/19 UBER *EATS              41.87
    07/22 AMZN Mktp US*8H2K3     129.99
    """;

    txns = parse_statement(raw);
    for t in txns {
        print(f"{t.merchant:<24} ${t.amount:>7.2f}  {t.category:<12} recurring={t.looks_recurring}");
    }
    print("\n" + spending_verdict(txns, monthly_income=5000.0));
}
