export type Role='customer'|'store_owner';
export type Medicine={id:string;name:string;generic_name:string|null;strength:string|null;form:string|null;requires_prescription:boolean};
export type CartItem={medicine:Medicine;quantity:number};
export type StoreOption={id:string;name:string;address:string;is_open:boolean;offers_delivery:boolean;distance_km?:number|null;missing_items?:string[]|null;total_price?:number|null};
export type OrderStatus='pending'|'accepted'|'rejected'|'ready'|'out_for_delivery'|'completed'|'cancelled'|'expired'|'not_collected';
export type Order={id:string;customer_id:string;store_id:string;fulfilment_type:'pickup'|'delivery';status:OrderStatus;total:number;handover_code:string;reject_reason:string|null;created_at:string;delivery_address:string|null};
