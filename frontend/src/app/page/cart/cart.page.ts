import { Component, inject } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatIconModule } from '@angular/material/icon';
import { RouterLink } from '@angular/router';

import { CartService } from '../../core/cart.service';

@Component({
  selector: 'app-cart-page',
  standalone: true,
  imports: [DecimalPipe, RouterLink, MatCardModule, MatButtonModule, MatIconModule],
  template: `
    <h1>Mi carrito</h1>

    @if (cart.items().length === 0) {
      <mat-card class="empty">
        <mat-card-content>
          <p>No hay productos en tu carrito.</p>
          <button mat-flat-button color="primary" routerLink="/catalog">Ir al catalogo</button>
        </mat-card-content>
      </mat-card>
    } @else {
      <mat-card>
        <mat-card-content>
          @for (item of cart.items(); track item.product.id) {
            <div class="line">
              <img [src]="item.product.image_url ?? placeholder" [alt]="item.product.name" class="thumb">
              <span class="grow name">{{ item.product.name }}</span>
              <div class="qty">
                <button mat-icon-button (click)="cart.updateQuantity(item.product.id, item.quantity - 1)" aria-label="Quitar una unidad">
                  <mat-icon>remove</mat-icon>
                </button>
                <span class="units">{{ item.quantity }}</span>
                <button mat-icon-button (click)="cart.updateQuantity(item.product.id, item.quantity + 1)" aria-label="Anadir una unidad">
                  <mat-icon>add</mat-icon>
                </button>
              </div>
              <span class="lineprice">{{ '$' }}{{ item.product.price * item.quantity | number:'1.2-2' }}</span>
              <button mat-icon-button (click)="cart.remove(item.product.id)" aria-label="Eliminar del carrito">
                <mat-icon>delete</mat-icon>
              </button>
            </div>
          }

          <div class="summary">
            <span>{{ cart.totalUnits() }} unidad(es)</span>
            <span class="total">Total: <strong>{{ '$' }}{{ cart.totalAmount() | number:'1.2-2' }}</strong></span>
          </div>
        </mat-card-content>
        <mat-card-actions>
          <button mat-flat-button color="primary" routerLink="/checkout">Ir a pagar</button>
          <button mat-stroked-button routerLink="/catalog">Seguir comprando</button>
          <button mat-button color="warn" (click)="cart.clear()">Vaciar carrito</button>
        </mat-card-actions>
      </mat-card>
    }
  `,
  styles: [`
    .line { display: flex; align-items: center; gap: 16px; padding: 12px 0; border-bottom: 1px solid #ececec; }
    .thumb { width: 56px; height: 56px; object-fit: cover; border-radius: 8px; }
    .name { font-weight: 500; }
    .grow { flex: 1; }
    .qty { display: flex; align-items: center; gap: 4px; }
    .units { min-width: 32px; text-align: center; font-weight: 600; }
    .lineprice { min-width: 96px; text-align: right; font-weight: 600; }
    .summary { display: flex; justify-content: flex-end; gap: 24px; align-items: baseline; margin-top: 16px; font-size: 16px; }
    .total { font-size: 18px; }
    .empty { max-width: 480px; margin-top: 24px; text-align: center; }
  `],
})
export class CartPage {
  readonly cart = inject(CartService);
  readonly placeholder = 'https://placehold.co/600x400?text=Producto';
}
