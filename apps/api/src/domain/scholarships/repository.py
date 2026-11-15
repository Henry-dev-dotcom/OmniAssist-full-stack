from src.domain.common.records import RecordRepo
from src.domain.scholarships.schemas import ScholarshipOut

_COLUMNS = (
    "region",
    "university",
    "program",
    "scheme",
    "portal_link",
    "opens_label",
    "deadline_at",
    "status",
    "documents_required",
    "cv_status",
    "transcripts_status",
    "letter_status",
    "references_status",
    "portal_status",
    "funding",
    "notes",
)

repo = RecordRepo(
    table="scholarship_applications",
    entity_type="scholarship_application",
    columns=_COLUMNS,
    updatable=_COLUMNS,
    out=ScholarshipOut,
    label="Scholarship application",
)
