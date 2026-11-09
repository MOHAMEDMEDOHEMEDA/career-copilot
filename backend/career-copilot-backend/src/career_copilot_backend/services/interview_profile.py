import re
from dataclasses import dataclass

MAX_PROFILE_SKILLS = 20
MAX_EXCERPT_LENGTH = 240
KNOWN_SKILLS = (
    "SwiftUI",
    "Swift",
    "Combine",
    "MVVM",
    "UIKit",
    "Swift Concurrency",
    "Python",
    "FastAPI",
    "Django",
    "PostgreSQL",
    "SQL",
    "Docker",
    "React",
    "TypeScript",
    "JavaScript",
    "Java",
    "Kotlin",
    "AWS",
    "REST",
    "GraphQL",
)


@dataclass(frozen=True)
class SupportedSkill:
    name: str
    evidence: str


@dataclass(frozen=True)
class CandidateContext:
    resume_skills: tuple[SupportedSkill, ...]
    selected_skills: tuple[str, ...]
    resume_context: tuple[str, ...]


def build_candidate_context(
    resume_text: str | None, selected_skills: list[str]
) -> CandidateContext:
    """Keep explicit user selections separate from exact, bounded resume evidence."""
    candidates = list(dict.fromkeys([*KNOWN_SKILLS, *selected_skills]))
    text = resume_text or ""
    result = []
    seen: set[str] = set()
    for skill in candidates:
        normalized = skill.strip().casefold()
        if not normalized or normalized in seen:
            continue
        match = re.search(
            r"(?<!\w)" + re.escape(skill.strip()) + r"(?!\w)", text, re.IGNORECASE
        )
        if match is None:
            continue
        seen.add(normalized)
        result.append(SupportedSkill(name=skill.strip(), evidence=match.group()))
        if len(result) == MAX_PROFILE_SKILLS:
            break
    selected = tuple(
        item.strip()[:MAX_EXCERPT_LENGTH]
        for item in selected_skills[:MAX_PROFILE_SKILLS]
        if item.strip()
    )
    snippets: list[str] = []
    for segment in re.split(r"(?<=[.!?])\s+|[\r\n]+", text):
        segment = segment.strip()
        if not re.search(
            r"\b(project|developed|built|implemented|maintained|designed|contributed|worked)\b",
            segment,
            re.IGNORECASE,
        ):
            continue
        if any(
            re.search(
                r"(?<!\w)" + re.escape(item.name) + r"(?!\w)", segment, re.IGNORECASE
            )
            for item in result
        ):
            snippets.append(segment[:MAX_EXCERPT_LENGTH])
            if len(snippets) == 3:
                break
    return CandidateContext(
        resume_skills=tuple(result),
        selected_skills=selected,
        resume_context=tuple(snippets),
    )
