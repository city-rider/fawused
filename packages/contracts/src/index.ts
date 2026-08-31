export type TrustStatus = 'used' | 'select' | 'approved';
export type ListingLifecycleStatus = 'draft' | 'published' | 'archived' | 'sold' | 'blocked' | 'deleted_soft';
export type VatStatus = 'with_vat' | 'without_vat';
export type Gearbox = 'manual' | 'robotized' | 'automatic';
export type VehicleType = 'tractor' | 'dump_truck' | 'chassis' | 'flatbed' | 'van' | 'refrigerated' | 'special' | 'other';

export interface PublicListingSummary {
  id: string;
  title: string;
  model: string;
  production_year: number;
  mileage_km: number;
  price_rub: number;
  vat_status: VatStatus;
  leasing_available: boolean;
  trust_status: TrustStatus;
  city: string;
  distance_km?: number | null;
  cover_photo_url?: string | null;
}

export interface CatalogQuery {
  model?: string;
  city?: string;
  radius_km?: 0 | 50 | 100 | 200 | 500 | 1000;
  year_from?: number;
  year_to?: number;
  mileage_from?: number;
  mileage_to?: number;
  price_from?: number;
  price_to?: number;
  trust_status?: TrustStatus;
  leasing_available?: boolean;
}
