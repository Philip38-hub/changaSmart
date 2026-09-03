from app.services.reconciliation import name_similarity, normalize_name


def test_normalize_name_lowercases_and_strips_punctuation():
    assert normalize_name("ANNE   Otieno.") == "anne otieno"
    assert normalize_name("Anne-Otieno") == "anne otieno"


def test_normalize_name_collapses_whitespace():
    assert normalize_name("  Jane   Wanjiku  ") == "jane wanjiku"


def test_name_similarity_identical_names_is_high():
    assert name_similarity("Jane Wanjiku", "jane wanjiku") == 1.0


def test_name_similarity_different_formatting_still_high():
    # Same person, different capitalization / punctuation from M-PESA vs.
    # how they're registered as a contributor.
    score = name_similarity("JANE WANJIKU", "Jane  Wanjiku.")
    assert score > 0.95


def test_name_similarity_different_people_is_low():
    score = name_similarity("Anne Otieno", "Jane Wanjiku")
    assert score < 0.5
