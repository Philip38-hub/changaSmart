"""Strands tools for reading project data."""

from __future__ import annotations

from strands import tool

from app.repositories.store import store


@tool
def get_project(project_id: str) -> dict:
    """Look up a fundraising project by id.

    Args:
        project_id: The project's id, e.g. "proj_ab12cd34ef56".

    Returns:
        The project's name, target amount, status, and creation time, or an
        error message if no such project exists.
    """
    project = store.projects.get(project_id)
    if project is None:
        return {"error": f"Project {project_id} not found"}
    return project.model_dump(mode="json")
