import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../utils/app_theme.dart';
import '../utils/app_helpers.dart';
import '../utils/web_image_loader.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback? onTap;
  final String? shopName;
  final VoidCallback? onShopTap;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.shopName,
    this.onShopTap,
  });

  @override
  Widget build(BuildContext context) {
    final safeShopName = (shopName ?? '').trim();
    final String? validImageUrl =
        product.images.where((url) => url.trim().isNotEmpty).isEmpty
            ? null
            : product.images.firstWhere((url) => url.trim().isNotEmpty);

    final bool isAvailable = product.isService
        ? product.isAvailable
        : (product.isAvailable && product.stock > 0);
    final bool inStock = product.isPhysicalProduct ? isAvailable : true;
    final bool isTopRated = product.rating >= 4.5 && product.reviewCount > 0;
    final bool isBestSeller = product.reviewCount >= 10;

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 255;
          final ultraCompact = constraints.maxHeight < 220;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: ultraCompact ? 7 : 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      validImageUrl != null
                          ? WebImageLoader.loadImage(
                              imageUrl: validImageUrl,
                              fit: BoxFit.cover,
                              placeholder: Container(
                                color: const Color(0xFFF5F5F5),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primaryPink,
                                  ),
                                ),
                              ),
                              errorWidget: Container(
                                color: const Color(0xFFF5F5F5),
                                child: const Icon(
                                  Icons.image_outlined,
                                  color: Colors.grey,
                                  size: 28,
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFFF5F5F5),
                              child: Icon(
                                product.isService
                                    ? Icons.design_services_outlined
                                    : Icons.shopping_bag_outlined,
                                size: 30,
                                color: Colors.grey,
                              ),
                            ),
                      if (isBestSeller || isTopRated)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isBestSeller
                                  ? AppTheme.primaryPurple
                                  : AppTheme.primaryOrange,
                              borderRadius: const BorderRadius.only(
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                            child: Text(
                              isBestSeller ? 'Best Seller' : 'Top Rated',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 8 : 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (product.isService)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFF9C27B0),
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                              ),
                            ),
                            child: Text(
                              'SERVICE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 8 : 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (product.isPhysicalProduct && !inStock)
                        Container(
                          color: Colors.black.withValues(alpha: 0.38),
                          child: Center(
                            child: Text(
                              'Out of\nStock',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: compact ? 10 : 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: ultraCompact ? 3 : 4,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      compact ? 4 : 6,
                      8,
                      compact ? 4 : 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: compact ? 11 : 12,
                            color: AppTheme.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        if (!ultraCompact && safeShopName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: onShopTap,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.storefront_rounded,
                                  size: 10,
                                  color: AppTheme.primaryPurple,
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    safeShopName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 8 : 9,
                                      color: AppTheme.primaryPurple,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!ultraCompact && product.reviewCount > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              ...List.generate(
                                5,
                                (i) => Icon(
                                  i < product.rating.round()
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: Colors.amber,
                                  size: compact ? 9 : 10,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '(${product.reviewCount})',
                                style: TextStyle(
                                  fontSize: compact ? 8 : 9,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Spacer(),
                        Text(
                          AppHelpers.formatCurrency(product.price),
                          style: TextStyle(
                            color: AppTheme.primaryPink,
                            fontWeight: FontWeight.bold,
                            fontSize: compact ? 13 : 14,
                          ),
                        ),
                        if (!ultraCompact && product.isPhysicalProduct && inStock && product.stock <= 5)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              'Only ${product.stock} left',
                              style: TextStyle(
                                fontSize: compact ? 8 : 9,
                                color: AppTheme.primaryPink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: double.infinity,
                          height: compact ? 23 : 27,
                          child: ElevatedButton(
                            onPressed: isAvailable ? onTap : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: product.isService
                                  ? const Color(0xFF9C27B0)
                                  : AppTheme.primaryOrange,
                              disabledBackgroundColor: Colors.grey[300],
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            child: Text(
                              isAvailable ? 'View' : 'Out of Stock',
                              style: TextStyle(
                                fontSize: compact ? 10 : 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
