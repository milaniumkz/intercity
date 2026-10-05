export const clientUserSelect = {
    id: true,
    publicId: true,
    phone: true,
    name: true,
    role: true,
    refCode: true,
    refLink: true,
    cityId: true,
    createdAt: true,
    updatedAt: true,
} as const;

export const adminUserSelect = {
    id: true,
    phone: true,
    name: true,
    role: true,
    refCode: true,
    refLink: true,
    referredBy: true,
    cityId: true,
    createdAt: true,
    updatedAt: true,
} as const;
