import { Injectable, computed, effect, signal } from '@angular/core';

export interface CartProduct { id: number; name: string; price: number; image_url: string | null; }
export interface CartItem { product: CartProduct; quantity: number; }

const STORAGE_KEY = 'techstore.cart.v1';

@Injectable({ providedIn: 'root' })
export class CartService {
  private readonly itemsSignal = signal<CartItem[]>(this.load());
  readonly items = computed(() => this.itemsSignal());
  readonly totalUnits = computed(() => this.itemsSignal().reduce((acc, i) => acc + i.quantity, 0));
  readonly totalAmount = computed(() => this.itemsSignal().reduce((acc, i) => acc + i.product.price * i.quantity, 0));

  constructor() {
    // Persiste automaticamente en localStorage any cambio del carrito (alta, cantidad o vaciado).
    effect(() => this.persist(this.itemsSignal()));
  }

  add(product: CartProduct, quantity = 1): void {
    this.itemsSignal.update((items) => {
      const existing = items.find((i) => i.product.id === product.id);
      if (existing) {
        return items.map((i) => i.product.id === product.id ? { ...i, quantity: i.quantity + quantity } : i);
      }
      return [...items, { product, quantity }];
    });
  }

  updateQuantity(productId: number, quantity: number): void {
    if (quantity <= 0) { this.remove(productId); return; }
    this.itemsSignal.update((items) => items.map((i) => i.product.id === productId ? { ...i, quantity } : i));
  }

  remove(productId: number): void {
    this.itemsSignal.update((items) => items.filter((i) => i.product.id !== productId));
  }

  clear(): void { this.itemsSignal.set([]); }

  private load(): CartItem[] {
    if (typeof window === 'undefined' || !window.localStorage) return [];
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw) as unknown;
      if (!Array.isArray(parsed)) return [];
      return parsed.filter(
        (i): i is CartItem =>
          typeof i === 'object' && i !== null && 'product' in i && 'quantity' in i
          && typeof (i as CartItem).quantity === 'number'
          && typeof (i as CartItem).product?.id === 'number',
      );
    } catch {
      // localStorage inhabilitado o JSON corrupto: se arranca con carrito vacio.
      return [];
    }
  }

  private persist(items: CartItem[]): void {
    if (typeof window === 'undefined' || !window.localStorage) return;
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
    } catch {
      // Almacenamiento lleno privado/bloqueado: el carrito sigue vivo solo en memoria.
    }
  }
}
