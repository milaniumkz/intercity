export function isIndividual(profile: { kind: string; countryCode: string } | null | undefined) {
    return profile?.countryCode === 'KZ' && profile.kind === 'INDIVIDUAL';
}

export function canWorkInKazakhstan(profile: { kind: string; countryCode: string; status: string; activities: string[] } | null | undefined) {
    return isIndividual(profile) || (profile?.countryCode === 'KZ' &&
        ['SELF_EMPLOYED', 'IE'].includes(profile.kind) && profile.status === 'VERIFIED' && profile.activities.includes('49320'));
}
