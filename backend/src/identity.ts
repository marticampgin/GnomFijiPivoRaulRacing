export const DEV_ISSUER = 'urn:gnom-fiji:dev';
export const DEV_PROFILES = Object.freeze([
  { id: 'dev-1', displayName: 'Driver 01' },
  { id: 'dev-2', displayName: 'Driver 02' },
  { id: 'dev-3', displayName: 'Driver 03' },
]);

export interface VerifiedIdentity { provider: 'dev' | 'google'; issuer: string; subject: string }
export interface IdentityProvider<Proof> { verify(proof: Proof): Promise<VerifiedIdentity> }

export class DevIdentityProvider implements IdentityProvider<{ profileId: string }> {
  async verify(proof: { profileId: string }): Promise<VerifiedIdentity> {
    if (!DEV_PROFILES.some((profile) => profile.id === proof.profileId)) throw new Error('Unrecognized dev profile');
    return { provider: 'dev', issuer: DEV_ISSUER, subject: proof.profileId };
  }
}
