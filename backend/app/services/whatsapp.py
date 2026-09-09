"""Deterministic WhatsApp-ready text generation.

No LLM involvement -- these are plain string templates over report data
that a human will later copy/paste (or a future "Copy" button will grab)
into a WhatsApp group.
"""

from __future__ import annotations

from app.models import PeriodType, TransactionStatus
from app.repositories.store import store
from app.services.reporting import generate_collection_report, generate_period_report


def _money_line(name: str, amount: int) -> str:
    return f"{name} — KSh {amount:,}"


def full_contribution_update(collection_id: str) -> str:
    report = generate_collection_report(collection_id)
    lines = [f"📢 {report.name} — Contribution Update", ""]

    if report.target_amount is not None:
        lines.append(f"Target: KSh {report.target_amount:,}")
    lines.append(f"Raised: KSh {report.total_received:,}")
    if report.remaining_amount is not None:
        lines.append(f"Remaining: KSh {report.remaining_amount:,}")
    lines.append(f"Status: {report.status.value}")

    paid = [e for e in report.contributor_breakdown if e.total_paid > 0]
    pending = [e for e in report.contributor_breakdown if e.total_paid == 0]

    if paid:
        lines += ["", "✅ Paid:"]
        for entry in sorted(paid, key=lambda e: e.total_paid, reverse=True):
            lines.append(_money_line(entry.name, entry.total_paid))

    if pending:
        lines += ["", "⏳ Pending:"]
        for entry in pending:
            expected = (
                f" (expected KSh {entry.expected_amount:,})"
                if entry.expected_amount
                else ""
            )
            lines.append(f"{entry.name}{expected}")

    if report.pending_review_count:
        lines += ["", f"⚠️ {report.pending_review_count} transaction(s) awaiting review"]

    return "\n".join(lines).strip()


def paid_list(collection_id: str) -> str:
    report = generate_collection_report(collection_id)
    paid = sorted(
        (e for e in report.contributor_breakdown if e.total_paid > 0),
        key=lambda e: e.total_paid,
        reverse=True,
    )
    lines = ["✅ Confirmed contributions:"]
    lines += [_money_line(e.name, e.total_paid) for e in paid] or ["None yet"]
    return "\n".join(lines)


def pending_list(collection_id: str) -> str:
    report = generate_collection_report(collection_id)
    pending = [e for e in report.contributor_breakdown if e.total_paid == 0]
    lines = ["⏳ Still waiting on:"]
    for entry in pending:
        expected = (
            f" (expected KSh {entry.expected_amount:,})"
            if entry.expected_amount
            else ""
        )
        lines.append(f"{entry.name}{expected}")
    if not pending:
        lines.append("Everyone has contributed 🎉")
    return "\n".join(lines)


def review_list(collection_id: str) -> str:
    flagged = [
        t
        for t in store.transactions.list_by_collection(collection_id)
        if t.status == TransactionStatus.NEEDS_REVIEW
    ]
    lines = ["⚠️ Needs review:"]
    for t in flagged:
        lines.append(
            f"{t.sender_name} — KSh {t.amount:,} ({t.mpesa_code}): "
            f"{t.review_reason or 'ambiguous match'}"
        )
    if not flagged:
        lines.append("None 🎉")
    return "\n".join(lines)


def harambee_progress_update(collection_id: str) -> str:
    report = generate_collection_report(collection_id)
    lines = ["🔥 HARAMBEE UPDATE", ""]

    if report.target_amount is not None:
        lines.append(f"Target: KSh {report.target_amount:,}")
    lines.append(f"Raised: KSh {report.total_received:,}")
    if report.remaining_amount is not None:
        lines.append(f"Remaining: KSh {report.remaining_amount:,}")

    leaders = sorted(
        (e for e in report.contributor_breakdown if e.total_paid > 0),
        key=lambda e: e.total_paid,
        reverse=True,
    )

    if leaders[:3]:
        lines += ["", "🏆 Current leaders:"]
        lines += [_money_line(e.name, e.total_paid) for e in leaders[:3]]

    others = leaders[3:]
    if others:
        lines += ["", "🙏 Other contributions:"]
        lines += [_money_line(e.name, e.total_paid) for e in others]

    return "\n".join(lines).strip()


def _format_date(d) -> str:
    return d.strftime("%d/%m")


_PERIOD_LABEL = {
    PeriodType.WEEKLY: "Week",
    PeriodType.FORTNIGHTLY: "Fortnight",
    PeriodType.MONTHLY: "Month",
}


def period_contribution_update(collection_id: str) -> str:
    """Copy-paste-ready period-by-period breakdown, formatted to match a
    typical manually-kept WhatsApp tracker: numbered names per period, a
    period total, and a running grand total. "Period" follows the
    collection's own configured cadence (Collection.period) -- a weekly
    chama gets "Week of ...", a monthly one gets "Month of ..."."""
    report = generate_period_report(collection_id)
    label = _PERIOD_LABEL[report.period]
    if not report.periods:
        return f"📢 {report.name} — {label}ly Update\n\nNo contributions recorded yet."

    lines = [f"📢 {report.name} — {label}ly Update", ""]
    for period in report.periods:
        lines.append(
            f"{label} of {_format_date(period.period_start)} - {_format_date(period.period_end)}"
        )
        for i, entry in enumerate(period.contributions, start=1):
            lines.append(f"{i}. {entry.name} — KSh {entry.amount:,}")
        lines.append(f"{label}ly total: KSh {period.period_total:,}")
        lines.append("")

    lines.append(f"Total: KSh {report.grand_total:,}")
    return "\n".join(lines).strip()
