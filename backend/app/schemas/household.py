from pydantic import BaseModel, Field
from typing import Optional


class CreateHouseholdIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class JoinHouseholdIn(BaseModel):
    invite_code: str = Field(min_length=8, max_length=8)


class HouseholdOut(BaseModel):
    id: int
    name: str
    invite_code: str
    created_by: int
    created_at: str


class MemberOut(BaseModel):
    user_id: int
    display_name: str
    role: str
    joined_at: str


class HouseholdDetailOut(BaseModel):
    household: HouseholdOut
    members: list[MemberOut]
    is_admin: bool


class InviteCodeOut(BaseModel):
    invite_code: str
