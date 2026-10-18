import { HttpClient } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { RouterLink } from '@angular/router';

import { SupabaseService } from '../../core/supabase.service';
import { CartService } from '../../core/cart.service';

interface CheckoutResult { order_id: number; status: string; total: number; reference: string; }

@Component({
  selector: 'app-checkout-page',
  standalone: true,
  imports: [DecimalPipe, MatCardModule, MatButtonModule, MatIconModule, RouterLink],
  template: `
    <h1>Checkout</h1>

    @if (cart.items().length === 0) {
      <p>Tu carrito esta vacio.</p>
      <button mat-flat-button color="primary" routerLink="/catalog">Ir al catalogo</button>
    } @else {
      <mat-card>
        <mat-card-content>
          @for (item of cart.items(); track item.product.id) {
            <div class="line">
              <span class="grow">{{ item.product.name }}</span>
              <span>x{{ item.quantity }}</span>
              <span class="lineprice">{{ '$' }}{{ item.product.price * item.quantity | number:'1.2-2' }}</span>
              <button mat-icon-button (click)="cart.remove(item.product.id)"><mat-icon>delete</mat-icon></button>
            </div>
          }
          <div class="total"><strong>Total: {{ '$' }}{{ cart.totalAmount() | number:'1.2-2' }}</strong></div>
        </mat-card-content>
        <mat-card-actions>
          <button mat-flat-button color="primary" (click)="confirm()" [disabled]="processing() || result()">
            @if (processing()) { Procesando... } @else { Confirmar compra }
          </button>
        </mat-card-actions>
      </mat-card>

      @if (result()) {
        <mat-card class="ok">
          <mat-card-content>
            <p>Orden registrada: <strong>#{{ result()?.order_id }}</strong></p>
            <p>Total: {{ '$' }}{{ result()?.total | number:'1.2-2' }} — Referencia: {{ result()?.reference }}</p>
            <button mat-flat-button routerLink="/profile">Ver mi historial</button>
            <button mat-button routerLink="/catalog">Seguir comprando</button>
          </mat-card-content>
        </mat-card>
      }

      @if (error()) { <p class="error">{{ error() }}</p> }
    }
  `,
  styles: [`
    .line { display: flex; align-items: center; gap: 12px; padding: 8px 0; border-bottom: 1px solid #ececec; }
    .grow { flex: 1; }
    .total { text-align: right; font-size: 18px; margin-top: 12px; }
    .ok { margin-top: 24px; background-color: #e8f5e9; }
    .error { color: #c62828; margin-top: 16px; }
  `],
})
export class CheckoutPage {
  private http = inject(HttpClient);
  private supabase = inject(SupabaseService);
  readonly cart = inject(CartService);

  readonly processing = signal(false);
  readonly result = signal<CheckoutResult | null>(null);
  readonly error = signal<string | null>(null);

  async confirm(): Promise<void> {
    this.processing.set(true);
    this.error.set(null);
    const body = {
      items: this.cart.items().map((i) => ({ product_id: i.product.id, quantity: i.quantity })),
    };
    this.http.post<CheckoutResult>('/api/orders/checkout', body).subscribe({
      next: (res) => {
        this.processing.set(false);
        this.result.set(res);
        this.cart.clear();
      },
      error: (err) => {
        this.processing.set(false);
        const detail = err.error?.detail;
        this.error.set(typeof detail === 'string' ? detail : 'No se pudo completar la compra');
      },
    });
  }
}
