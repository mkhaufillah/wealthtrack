
from pydantic import BaseModel, EmailStr, Field


class UserRegister(BaseModel):
    email: EmailStr
    otp_code: str = Field(min_length=6, max_length=6)
    username: str = Field(min_length=3, max_length=32)
    display_name: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=6, max_length=128)


class SendOtpIn(BaseModel):
    email: EmailStr


class UserLogin(BaseModel):
    username: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class UpdateProfileIn(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=64)
    cycle_start_day: int | None = Field(default=None, ge=1, le=28)
    email: EmailStr | None = Field(default=None)
    locale: str | None = Field(default=None, max_length=16)


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str = Field(min_length=6, max_length=128)


class MessageOut(BaseModel):
    message: str
